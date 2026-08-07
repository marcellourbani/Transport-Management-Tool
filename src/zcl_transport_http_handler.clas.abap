CLASS zcl_transport_http_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.

    " -------------------------------------------------------------------
    " URL path suffixes (relative to the SICF service /sap/bc/ztransportmanagement)
    " -------------------------------------------------------------------
    CONSTANTS:
      BEGIN OF c_path,
        download TYPE string VALUE '/download',
        upload   TYPE string VALUE '/upload',
        import   TYPE string VALUE '/import',
        populate TYPE string VALUE '/populate',
      END OF c_path.

    " -------------------------------------------------------------------
    " HTTP status codes used by this handler
    " -------------------------------------------------------------------
    CONSTANTS:
      BEGIN OF c_status,
        ok                 TYPE i VALUE 200,
        bad_request        TYPE i VALUE 400,
        not_found          TYPE i VALUE 404,
        method_not_allowed TYPE i VALUE 405,
        internal_error     TYPE i VALUE 500,
      END OF c_status.

    CONSTANTS c_content_type_json TYPE string VALUE 'application/json; charset=utf-8'.
    CONSTANTS c_method_post       TYPE string VALUE 'POST'.

    " -------------------------------------------------------------------
    " Wire types for JSON (in-out)
    " -------------------------------------------------------------------
    TYPES:
      BEGIN OF ty_trkorr_request,
        trkorr TYPE trkorr,
      END OF ty_trkorr_request.

    TYPES:
      BEGIN OF ty_download_response,
        trkorr     TYPE trkorr,
        zip_base64 TYPE string,
      END OF ty_download_response.

    TYPES:
      BEGIN OF ty_upload_request,
        zip_base64 TYPE string,
      END OF ty_upload_request.

    TYPES:
      BEGIN OF ty_upload_response,
        trkorr TYPE trkorr,
      END OF ty_upload_response.

    TYPES:
      BEGIN OF ty_status_response,
        status TYPE string,
      END OF ty_status_response.

    TYPES tt_stdout_line TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_populate_response,
        status         TYPE string,
        tp_return_code TYPE i,
        tp_message     TYPE string,
        stdout         TYPE tt_stdout_line,
      END OF ty_populate_response.

    TYPES:
      BEGIN OF ty_error_body,
        message     TYPE string,
        return_code TYPE i,
        stdout      TYPE tt_stdout_line,
      END OF ty_error_body.

    TYPES:
      BEGIN OF ty_error_response,
        error TYPE ty_error_body,
      END OF ty_error_response.

    DATA mo_request  TYPE REF TO if_http_request.
    DATA mo_response TYPE REF TO if_http_response.

    " -------------------------------------------------------------------
    " Per-operation methods — each may ONLY raise zcx_transport_http.
    " Any zcx_transport_manager_message coming from the operations class
    " is caught and translated into zcx_transport_http by wrap_business_ex.
    " -------------------------------------------------------------------
    METHODS handle_download
      RAISING zcx_transport_http.

    METHODS handle_upload
      RAISING zcx_transport_http.

    METHODS handle_import
      RAISING zcx_transport_http.

    METHODS handle_populate
      RAISING zcx_transport_http.

    " -------------------------------------------------------------------
    " Helpers
    " -------------------------------------------------------------------
    METHODS require_post
      RAISING zcx_transport_http.

    METHODS parse_trkorr_body
      RETURNING VALUE(rv_trkorr) TYPE trkorr
      RAISING   zcx_transport_http.

    METHODS write_json_response
      IMPORTING iv_json   TYPE string
                iv_status TYPE i DEFAULT c_status-ok.

    "! Central exception-response helper. Called by the top-level
    "! TRY/CATCH in handle_request — turns any zcx_transport_http into
    "! a JSON error body with the HTTP status set to
    "! io_exception->mv_return_code. If the previous exception is a
    "! zcx_transport_manager_message with captured tp stdout, the stdout
    "! lines are appended to the error body for diagnostics.
    METHODS write_exception_response
      IMPORTING io_exception TYPE REF TO zcx_transport_http.

    "! Translates a business exception coming out of ZCL_TRANSPORT_MANAGER
    "! into a zcx_transport_http. Always raises — used inline right after
    "! CATCH zcx_transport_manager_message.
    METHODS wrap_business_exception
      IMPORTING io_ex          TYPE REF TO zcx_transport_manager_message
                iv_return_code TYPE i DEFAULT c_status-bad_request
      RAISING   zcx_transport_http.

ENDCLASS.


CLASS zcl_transport_http_handler IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    " Central entry point:
    "   * routes by URL path suffix
    "   * catches ALL exceptions in one place (centralised handling)
    "   * uses write_exception_response as the single response helper
    "     for any zcx_transport_http error
    DATA lo_http_ex   TYPE REF TO zcx_transport_http.
    DATA lo_root_ex   TYPE REF TO cx_root.
    DATA lo_synthetic TYPE REF TO zcx_transport_http.
    DATA lv_path      TYPE string.

    mo_request  = server->request.
    mo_response = server->response.

    TRY.
        lv_path = mo_request->get_header_field( '~path_info' ).

        CASE lv_path.
          WHEN c_path-download.
            handle_download( ).
          WHEN c_path-upload.
            handle_upload( ).
          WHEN c_path-import.
            handle_import( ).
          WHEN c_path-populate.
            handle_populate( ).
          WHEN OTHERS.
            zcx_transport_http=>raise(
              iv_message     =
                |Unknown operation path "{ lv_path }". |
             && |Use /download, /upload, /import or /populate.|
              iv_return_code = c_status-not_found ).
        ENDCASE.

      CATCH zcx_transport_http INTO lo_http_ex.
        write_exception_response( lo_http_ex ).

      CATCH cx_root INTO lo_root_ex.
        " Safety net for anything unexpected — never let a raw
        " exception escape the handler.
        lo_synthetic = NEW zcx_transport_http(
          iv_message     = lo_root_ex->get_text( )
          iv_return_code = c_status-internal_error
          previous       = lo_root_ex ).
        write_exception_response( lo_synthetic ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_download.
    DATA lv_trkorr TYPE trkorr.
    DATA lv_zip    TYPE xstring.
    DATA ls_resp   TYPE ty_download_response.
    DATA lv_json   TYPE string.
    DATA lo_mgr    TYPE REF TO zcl_transport_manager.
    DATA lo_biz    TYPE REF TO zcx_transport_manager_message.

    require_post( ).
    lv_trkorr = parse_trkorr_body( ).

    TRY.
        lo_mgr = NEW zcl_transport_manager( ).
        lv_zip = lo_mgr->download_request( iv_request = lv_trkorr ).
      CATCH zcx_transport_manager_message INTO lo_biz.
        wrap_business_exception( lo_biz ).
    ENDTRY.

    ls_resp-trkorr     = lv_trkorr.
    ls_resp-zip_base64 = cl_http_utility=>encode_x_base64( lv_zip ).

    lv_json = /ui2/cl_json=>serialize(
      data        = ls_resp
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    write_json_response( iv_json   = lv_json
                         iv_status = c_status-ok ).
  ENDMETHOD.

  METHOD handle_upload.
    DATA lv_body    TYPE string.
    DATA ls_req     TYPE ty_upload_request.
    DATA lv_zip     TYPE xstring.
    DATA lv_trkorr  TYPE trkorr.
    DATA ls_resp    TYPE ty_upload_response.
    DATA lv_json    TYPE string.
    DATA lo_mgr     TYPE REF TO zcl_transport_manager.
    DATA lo_biz     TYPE REF TO zcx_transport_manager_message.

    require_post( ).

    lv_body = mo_request->get_cdata( ).
    IF lv_body IS INITIAL.
      zcx_transport_http=>raise(
        iv_message     = 'Request body is empty. Expected JSON with "zip_base64".'
        iv_return_code = c_status-bad_request ).
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = lv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-low_case
          CHANGING  data        = ls_req ).
      CATCH cx_root.
        zcx_transport_http=>raise(
          iv_message     = 'Invalid JSON body. Expected { "zip_base64": "..." }.'
          iv_return_code = c_status-bad_request ).
    ENDTRY.

    IF ls_req-zip_base64 IS INITIAL.
      zcx_transport_http=>raise(
        iv_message     = 'Field "zip_base64" is empty.'
        iv_return_code = c_status-bad_request ).
    ENDIF.

    lv_zip = cl_http_utility=>decode_x_base64( ls_req-zip_base64 ).

    TRY.
        lo_mgr = NEW zcl_transport_manager( ).
        lo_mgr->upload_request( EXPORTING iv_zip     = lv_zip
                                IMPORTING ev_request = lv_trkorr ).
      CATCH zcx_transport_manager_message INTO lo_biz.
        wrap_business_exception( lo_biz ).
    ENDTRY.

    ls_resp-trkorr = lv_trkorr.
    lv_json = /ui2/cl_json=>serialize(
      data        = ls_resp
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    write_json_response( iv_json   = lv_json
                         iv_status = c_status-ok ).
  ENDMETHOD.

  METHOD handle_import.
    DATA lv_trkorr TYPE trkorr.
    DATA ls_resp   TYPE ty_status_response.
    DATA lv_json   TYPE string.
    DATA lo_mgr    TYPE REF TO zcl_transport_manager.
    DATA lo_biz    TYPE REF TO zcx_transport_manager_message.

    require_post( ).
    lv_trkorr = parse_trkorr_body( ).

    TRY.
        lo_mgr = NEW zcl_transport_manager( ).
        lo_mgr->import_request( iv_request = lv_trkorr ).
      CATCH zcx_transport_manager_message INTO lo_biz.
        wrap_business_exception( lo_biz ).
    ENDTRY.

    ls_resp-status = 'ok'.
    lv_json = /ui2/cl_json=>serialize(
      data        = ls_resp
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    write_json_response( iv_json   = lv_json
                         iv_status = c_status-ok ).
  ENDMETHOD.

  METHOD handle_populate.
    DATA lv_trkorr TYPE trkorr.
    DATA lv_rc     TYPE stpa-retcode.
    DATA lv_msg    TYPE stpa-message.
    DATA lt_stdout TYPE zcx_transport_manager_message=>tt_stdout.
    DATA ls_resp   TYPE ty_populate_response.
    DATA lv_json   TYPE string.
    DATA lo_mgr    TYPE REF TO zcl_transport_manager.
    DATA lo_biz    TYPE REF TO zcx_transport_manager_message.
    FIELD-SYMBOLS <fs_stdout> LIKE LINE OF lt_stdout.

    require_post( ).
    lv_trkorr = parse_trkorr_body( ).

    TRY.
        lo_mgr = NEW zcl_transport_manager( ).
        lo_mgr->populate_request_tables(
          EXPORTING iv_request        = lv_trkorr
          IMPORTING ev_tp_return_code = lv_rc
                    ev_tp_message     = lv_msg
                    et_stdout         = lt_stdout ).
      CATCH zcx_transport_manager_message INTO lo_biz.
        wrap_business_exception( lo_biz ).
    ENDTRY.

    ls_resp-status         = 'ok'.
    ls_resp-tp_return_code = lv_rc.
    ls_resp-tp_message     = lv_msg.
    LOOP AT lt_stdout ASSIGNING <fs_stdout>.
      APPEND CONV string( <fs_stdout>-line ) TO ls_resp-stdout.
    ENDLOOP.

    lv_json = /ui2/cl_json=>serialize(
      data        = ls_resp
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    write_json_response( iv_json   = lv_json
                         iv_status = c_status-ok ).
  ENDMETHOD.

  METHOD require_post.
    DATA(lv_method) = mo_request->get_header_field( '~request_method' ).
    TRANSLATE lv_method TO UPPER CASE.
    IF lv_method <> c_method_post.
      zcx_transport_http=>raise(
        iv_message     = |Method "{ lv_method }" not allowed. Use POST with a JSON body.|
        iv_return_code = c_status-method_not_allowed ).
    ENDIF.
  ENDMETHOD.

  METHOD parse_trkorr_body.
    DATA lv_body TYPE string.
    DATA ls_req  TYPE ty_trkorr_request.

    lv_body = mo_request->get_cdata( ).
    IF lv_body IS INITIAL.
      zcx_transport_http=>raise(
        iv_message     = 'Request body is empty. Expected JSON with "trkorr".'
        iv_return_code = c_status-bad_request ).
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = lv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-low_case
          CHANGING  data        = ls_req ).
      CATCH cx_root.
        zcx_transport_http=>raise(
          iv_message     = 'Invalid JSON body. Expected { "trkorr": "..." }.'
          iv_return_code = c_status-bad_request ).
    ENDTRY.

    IF ls_req-trkorr IS INITIAL.
      zcx_transport_http=>raise(
        iv_message     = 'Field "trkorr" is empty.'
        iv_return_code = c_status-bad_request ).
    ENDIF.

    rv_trkorr = ls_req-trkorr.
  ENDMETHOD.

  METHOD write_json_response.
    mo_response->set_status( code   = iv_status
                             reason = COND #( WHEN iv_status = c_status-ok THEN 'OK' ELSE '' ) ).
    mo_response->set_content_type( content_type = c_content_type_json ).
    mo_response->set_cdata( data = iv_json ).
  ENDMETHOD.

  METHOD write_exception_response.
    " Centralised exception-response helper. Serializes the exception
    " into a JSON error body and sets the HTTP status from the return
    " code carried by the exception. If a previous business exception
    " is present, its captured tp stdout is included for diagnostics.
    DATA ls_body TYPE ty_error_response.
    DATA lv_json TYPE string.
    DATA lv_status TYPE i.
    DATA lo_biz  TYPE REF TO zcx_transport_manager_message.
    FIELD-SYMBOLS <fs_stdout> TYPE tpstdout.

    ls_body-error-message     = io_exception->mv_message.
    ls_body-error-return_code = io_exception->mv_return_code.

    " If the exception wraps a business exception carrying tp stdout,
    " surface those diagnostic lines.
    IF io_exception->previous IS INSTANCE OF zcx_transport_manager_message.
      lo_biz ?= io_exception->previous.
      LOOP AT lo_biz->mt_stdout ASSIGNING <fs_stdout>.
        APPEND CONV string( <fs_stdout>-line ) TO ls_body-error-stdout.
      ENDLOOP.
    ENDIF.

    lv_json = /ui2/cl_json=>serialize(
      data        = ls_body
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-low_case ).

    " If the exception has an unset/invalid return code, fall back to
    " 500 so we never emit an HTTP 0.
    lv_status = COND #( WHEN io_exception->mv_return_code BETWEEN 100 AND 599
                        THEN io_exception->mv_return_code
                        ELSE c_status-internal_error ).

    write_json_response( iv_json   = lv_json
                         iv_status = lv_status ).
  ENDMETHOD.

  METHOD wrap_business_exception.
    " Translate ZCX_TRANSPORT_MANAGER_MESSAGE → ZCX_TRANSPORT_HTTP.
    " Preserves the original as 'previous' so write_exception_response
    " can still pull tp stdout for the response body.
    zcx_transport_http=>raise(
      iv_message     = io_ex->get_text( )
      iv_return_code = iv_return_code
      previous       = io_ex ).
  ENDMETHOD.

ENDCLASS.
