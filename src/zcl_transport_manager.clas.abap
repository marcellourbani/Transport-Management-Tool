CLASS zcl_transport_manager DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES tt_stdout TYPE zcx_transport_manager_message=>tt_stdout.

    METHODS constructor
      RAISING zcx_transport_manager_message.

    "! Reads the cofile/data files of a released TR from DIR_TRANS
    "! and returns them packaged as a single ZIP as raw bytes.
    METHODS download_request
      IMPORTING iv_request    TYPE trkorr
      RETURNING VALUE(rv_zip) TYPE xstring
      RAISING   zcx_transport_manager_message.

    "! Extracts the cofile/data files from a ZIP payload and lands
    "! them into the appropriate DIR_TRANS subfolders. The TR
    "! number recovered from the ZIP is returned in ev_request.
    METHODS upload_request
      IMPORTING iv_zip     TYPE xstring
      EXPORTING ev_request TYPE trkorr
      RAISING   zcx_transport_manager_message.

    "! Appends the TR to the STMS import buffer and triggers a
    "! full import (customizing requests get the FILLCLIENT step).
    METHODS import_request
      IMPORTING iv_request TYPE trkorr
      RAISING   zcx_transport_manager_message.

    "! Appends the TR to the STMS import buffer and runs only the
    "! object-list import phase (tp CMD) to populate E070/E071/E07T/
    "! E071K without performing a real import. Populates
    "! ev_tp_return_code, ev_tp_message and et_stdout with the tp
    "! results on success.
    METHODS populate_request_tables
      IMPORTING iv_request        TYPE trkorr
      EXPORTING ev_tp_return_code TYPE stpa-retcode
                ev_tp_message     TYPE stpa-message
                et_stdout         TYPE tt_stdout
      RAISING   zcx_transport_manager_message.

  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF mc_paths,
        cofiles TYPE string VALUE 'cofiles',
        data    TYPE string VALUE 'data',
      END OF mc_paths.

    CONSTANTS:
      BEGIN OF mc_file_types,
        cofile TYPE c LENGTH 1 VALUE 'K',
        data   TYPE c LENGTH 1 VALUE 'R',
        all    TYPE c LENGTH 2 VALUE 'KR',
      END OF mc_file_types.

    CONSTANTS:
      BEGIN OF mc_transport_category,
        cust TYPE string VALUE 'CUST',
        syst TYPE string VALUE 'SYST',
      END OF mc_transport_category.

    TYPES:
      BEGIN OF ty_file,
        name      TYPE string,
        content   TYPE xstring,
        file_type TYPE c LENGTH 1,
      END OF ty_file.

    TYPES tt_file TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY.

    METHODS get_req_files_from_server
      IMPORTING iv_request     TYPE trkorr
      RETURNING VALUE(rt_file) TYPE tt_file
      RAISING   zcx_transport_manager_message.

    METHODS get_req_files_from_client_zip
      IMPORTING iv_zip         TYPE xstring
      EXPORTING ev_request     TYPE trkorr
      RETURNING VALUE(rt_file) TYPE tt_file
      RAISING   zcx_transport_manager_message.

    DATA mo_server_file_manager TYPE REF TO lif_file_manager.

ENDCLASS.


CLASS zcl_transport_manager IMPLEMENTATION.

  METHOD constructor.
    mo_server_file_manager = NEW lcl_server_file_manager( ).
  ENDMETHOD.

  METHOD download_request.
    " Checks if TR is released, zips cofile/data, and returns the ZIP bytes.
    DATA lo_zip  TYPE REF TO cl_abap_zip.
    DATA lt_file TYPE tt_file.
    FIELD-SYMBOLS <fs_file> LIKE LINE OF lt_file.

    SELECT SINGLE COUNT(*) FROM e070
      WHERE trkorr   = @iv_request
        AND trstatus = @sctsc_state_released.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise( 'Action Aborted: Only RELEASED transport requests can be downloaded.' ).
    ENDIF.

    lt_file = get_req_files_from_server( iv_request ).
    lo_zip  = NEW cl_abap_zip( ).

    LOOP AT lt_file ASSIGNING <fs_file>.
      lo_zip->add( name    = <fs_file>-name
                   content = <fs_file>-content ).
    ENDLOOP.

    rv_zip = lo_zip->save( ).
  ENDMETHOD.

  METHOD upload_request.
    " Unzips the provided payload and writes each file to the correct
    " server subfolder under DIR_TRANS. Returns the TR number that was
    " recovered from the ZIP.
    DATA lv_filename  TYPE string.
    DATA lv_seperator TYPE string.
    DATA lt_file      TYPE tt_file.
    FIELD-SYMBOLS <fs_file> LIKE LINE OF lt_file.

    lv_seperator = mo_server_file_manager->get_seperator( ).
    lt_file      = get_req_files_from_client_zip( EXPORTING iv_zip     = iv_zip
                                                  IMPORTING ev_request = ev_request ).
    LOOP AT lt_file ASSIGNING <fs_file>.
      lv_filename = COND #( WHEN <fs_file>-file_type = mc_file_types-cofile THEN mc_paths-cofiles
                            WHEN <fs_file>-file_type = mc_file_types-data   THEN mc_paths-data
                            ELSE                                                 '' ).

      IF lv_filename IS INITIAL.
        CONTINUE.
      ENDIF.

      CONCATENATE lv_filename <fs_file>-name INTO lv_filename SEPARATED BY lv_seperator.
      mo_server_file_manager->write( iv_file = lv_filename
                                     iv_data = <fs_file>-content ).
    ENDLOOP.
  ENDMETHOD.

  METHOD import_request.
    " Appends TR to buffer and triggers STMS import.
    DATA lt_request TYPE stms_wbo_requests.
    DATA lv_system  TYPE tmsbuffer-sysnam.
    DATA lv_client  TYPE tmsbuffer-tarcli.
    DATA lv_request TYPE tmsbuffer-trkorr.
    FIELD-SYMBOLS <fs_request> LIKE LINE OF lt_request.

    lv_system  = sy-sysid.
    lv_client  = sy-mandt.
    lv_request = iv_request.

    CALL FUNCTION 'TR_AUTHORITY_CHECK_ADMIN'
      EXPORTING  iv_adminfunction = 'TADD'
      EXCEPTIONS OTHERS           = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'TMS_UI_APPEND_TR_REQUEST'
      EXPORTING  iv_system      = lv_system
                 iv_request     = lv_request
                 iv_expert_mode = 'X'
                 iv_ctc_active  = 'X'
      EXCEPTIONS OTHERS         = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'TMS_MGR_READ_TRANSPORT_REQUEST'
      EXPORTING  iv_request       = lv_request
                 iv_target_system = lv_system
      IMPORTING  et_request_infos = lt_request
      EXCEPTIONS OTHERS           = 1.

    ASSIGN lt_request[ 1 ] TO <fs_request>.
    IF sy-subrc = 0 AND <fs_request>-e070-korrdev = mc_transport_category-cust.
      CALL FUNCTION 'TMS_MGR_MAINTAIN_TR_QUEUE'
        EXPORTING  iv_command = 'FILLCLIENT'
                   iv_system  = lv_system
                   iv_request = lv_request
                   iv_tarcli  = lv_client
        EXCEPTIONS OTHERS     = 1.
    ENDIF.

    CALL FUNCTION 'TR_AUTHORITY_CHECK_ADMIN'
      EXPORTING  iv_adminfunction = 'IMPS'
      EXCEPTIONS OTHERS           = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'TMS_UI_IMPORT_TR_REQUEST'
      EXPORTING  iv_system      = lv_system
                 iv_request     = lv_request
                 iv_tarcli      = lv_client
                 iv_some_active = space
      EXCEPTIONS OTHERS         = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.
  ENDMETHOD.

  METHOD populate_request_tables.
    " Appends TR to buffer and populates E07* tables via tp CMD
    " (object-list import phase) WITHOUT performing a real import.
    DATA lv_system   TYPE tmsbuffer-sysnam.
    DATA lv_client   TYPE tmsbuffer-tarcli.
    DATA lv_request  TYPE tmsbuffer-trkorr.
    DATA lv_rc       TYPE stpa-retcode.
    DATA lv_msg      TYPE stpa-message.
    DATA lt_stdout   TYPE tt_stdout.
    DATA lv_syst_msg TYPE c LENGTH 200.

    CLEAR: ev_tp_return_code, ev_tp_message, et_stdout.

    lv_system  = sy-sysid.
    lv_client  = sy-mandt.
    lv_request = iv_request.

    CALL FUNCTION 'TR_AUTHORITY_CHECK_ADMIN'
      EXPORTING  iv_adminfunction = 'TADD'
      EXCEPTIONS OTHERS           = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'TMS_UI_APPEND_TR_REQUEST'
      EXPORTING  iv_system      = lv_system
                 iv_request     = lv_request
                 iv_expert_mode = 'X'
                 iv_ctc_active  = 'X'
      EXCEPTIONS OTHERS         = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'TRINT_TP_INTERFACE'
      EXPORTING  iv_tp_command                = 'CMD'
                 iv_system_name               = lv_system
                 iv_transport_request         = lv_request
                 iv_client                    = lv_client
      IMPORTING  ev_tp_return_code            = lv_rc
                 ev_tp_message                = lv_msg
      TABLES     tt_stdout                    = lt_stdout
      EXCEPTIONS unsupported_tp_command       = 1
                 invalid_tp_command           = 2
                 missing_parameter            = 3
                 invalid_parameter            = 4
                 get_tpparam_failed           = 5
                 update_tp_destination_failed = 6
                 get_tms_info_failed          = 7
                 permission_denied            = 8
                 tp_call_failed               = 9
                 insert_tpstat_failed         = 10
                 insert_tplog_failed          = 11
                 OTHERS                       = 12.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              INTO lv_syst_msg
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
      zcx_transport_manager_message=>raise_tp_failure(
        iv_message = CONV string( lv_syst_msg )
        it_stdout  = lt_stdout ).
    ENDIF.

    IF lv_rc > 4.
      zcx_transport_manager_message=>raise_tp_failure(
        iv_message = |Populate failed (tp RC={ lv_rc }): { lv_msg }|
        it_stdout  = lt_stdout ).
    ENDIF.

    ev_tp_return_code = lv_rc.
    ev_tp_message     = lv_msg.
    et_stdout         = lt_stdout.
  ENDMETHOD.

  METHOD get_req_files_from_server.
    " Reads the cofile and data file for a TR from DIR_TRANS.
    DATA lv_seperator TYPE string.
    DATA lv_file      TYPE string.
    FIELD-SYMBOLS <fs_file> LIKE LINE OF rt_file.

    lv_file      = |{ iv_request+4 }.{ iv_request(3) }|.
    lv_seperator = mo_server_file_manager->get_seperator( ).

    APPEND INITIAL LINE TO rt_file ASSIGNING <fs_file>.
    <fs_file>-name      = |{ mc_file_types-cofile }{ lv_file }|.
    <fs_file>-file_type = mc_file_types-cofile.
    <fs_file>-content   = mo_server_file_manager->read(
      |{ mc_paths-cofiles }{ lv_seperator }{ <fs_file>-name }| ).

    APPEND INITIAL LINE TO rt_file ASSIGNING <fs_file>.
    <fs_file>-name      = |{ mc_file_types-data }{ lv_file }|.
    <fs_file>-file_type = mc_file_types-data.
    <fs_file>-content   = mo_server_file_manager->read(
      |{ mc_paths-data }{ lv_seperator }{ <fs_file>-name }| ).
  ENDMETHOD.

  METHOD get_req_files_from_client_zip.
    " Parses the uploaded ZIP payload and returns the cofile + data files
    " plus the TR number recovered from the file names.
    DATA lo_zip    TYPE REF TO cl_abap_zip.
    DATA lv_prefix TYPE string.
    DATA lv_suffix TYPE string.
    FIELD-SYMBOLS <fs_zip>  LIKE LINE OF lo_zip->files.
    FIELD-SYMBOLS <fs_file> LIKE LINE OF rt_file.

    CLEAR ev_request.

    lo_zip = NEW cl_abap_zip( ).
    lo_zip->load( EXPORTING  zip    = iv_zip
                  EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    LOOP AT lo_zip->files ASSIGNING <fs_zip>.
      IF <fs_zip>-name NA mc_file_types-all.
        CONTINUE.
      ENDIF.

      APPEND INITIAL LINE TO rt_file ASSIGNING <fs_file>.
      <fs_file>-name      = <fs_zip>-name.
      <fs_file>-file_type = <fs_zip>-name(1).

      lo_zip->get( EXPORTING  name    = <fs_zip>-name
                   IMPORTING  content = <fs_file>-content
                   EXCEPTIONS OTHERS  = 1 ).

      IF ev_request IS INITIAL.
        SPLIT <fs_file>-name AT '.' INTO lv_prefix lv_suffix.
        IF sy-subrc = 0.
          ev_request = lv_suffix && mc_file_types-cofile && lv_prefix+1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF NOT line_exists( rt_file[ file_type = mc_file_types-cofile ] ).
      zcx_transport_manager_message=>raise( 'Structure Error: TR Header (Cofile) missing in ZIP.' ).
    ENDIF.

    IF NOT line_exists( rt_file[ file_type = mc_file_types-data ] ).
      zcx_transport_manager_message=>raise( 'Structure Error: TR Data (Data) missing in ZIP.' ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
