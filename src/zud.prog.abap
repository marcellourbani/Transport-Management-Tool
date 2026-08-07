* ----
*& Report ZUD - Transport Management Tool
* ----
*& Purpose: Facilitates the download of released Transport Requests (TR)
*& to the local client as ZIP files and supports uploading/importing TRs
*& from local files back to the SAP server.
*&
*& All business logic is delegated to ZCL_TRANSPORT_MANAGER. This report
*& only owns the selection screen and the client-PC file I/O needed to
*& hand the ZIP bytes to / receive them from the user's PC.
* ----
REPORT zud.

" -----------------------------------------------------------------------
" Selection Screen Definition
" -----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t01.
  PARAMETERS p_upload RADIOBUTTON GROUP gr1 USER-COMMAND uc1 DEFAULT 'X'.
  PARAMETERS p_downld RADIOBUTTON GROUP gr1.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE t02.
  " Download Parameters
  PARAMETERS p_trkorr TYPE trkorr MODIF ID m1.
  PARAMETERS p_folder TYPE string MODIF ID m1 LOWER CASE.

  " Upload Parameters
  PARAMETERS p_filenm TYPE string MODIF ID m2 LOWER CASE.
  PARAMETERS p_imprt  RADIOBUTTON GROUP gr2 MODIF ID m2 DEFAULT 'X'.
  PARAMETERS p_pop    RADIOBUTTON GROUP gr2 MODIF ID m2.
  PARAMETERS p_noimp  RADIOBUTTON GROUP gr2 MODIF ID m2.
SELECTION-SCREEN END OF BLOCK b2.


" -----------------------------------------------------------------------
" CLASS lcl_application
" Purpose: UI logic, selection-screen handling, entry point.
" All business logic (download/upload/import/populate) is delegated to
" ZCL_TRANSPORT_MANAGER; this class only owns the frontend PC I/O needed
" to bridge between the user's desktop and the operations class (which
" works exclusively in xstring bytes).
" -----------------------------------------------------------------------
CLASS lcl_application DEFINITION.
  PUBLIC SECTION.
    METHODS initialization.
    METHODS start_of_selection.
    METHODS at_selection_screen_output.
    METHODS at_selection_screen_for_folder.
    METHODS at_selection_screen_for_file.
    METHODS at_selection_screen_for_trkorr.

  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF mc_modif_ids,
        download TYPE c LENGTH 2 VALUE 'M1',
        upload   TYPE c LENGTH 2 VALUE 'M2',
      END OF mc_modif_ids.

    CONSTANTS:
      BEGIN OF mc_texts,
        request  TYPE string VALUE 'Transport Request',
        folder   TYPE string VALUE 'Target Local Folder',
        file     TYPE string VALUE 'Source ZIP File',
        t01      TYPE string VALUE 'Operation Mode',
        t02      TYPE string VALUE 'Configuration',
        upload   TYPE string VALUE 'Upload to Server',
        download TYPE string VALUE 'Download to Client',
        import   TYPE string VALUE 'Import after Upload',
        populate TYPE string VALUE 'Populate Transport Tables Only',
        no_imp   TYPE string VALUE 'No Import Action',
      END OF mc_texts.

    CONSTANTS:
      BEGIN OF mc_messages,
        download_ok                TYPE string VALUE 'SUCCESS: Transport downloaded successfully.',
        upload_ok                  TYPE string VALUE 'SUCCESS: Transport uploaded to server.',
        import_ok                  TYPE string VALUE 'SUCCESS: Import process triggered.',
        populate_ok                TYPE string VALUE 'SUCCESS: Transport tables populated (no import performed).',
        request_must_be_provided   TYPE string VALUE 'Error: Please specify a Transport Request.',
        file_name_must_be_provided TYPE string VALUE 'Error: Source ZIP file path is required.',
        folder_must_be_provided    TYPE string VALUE 'Error: Target folder path is required.',
      END OF mc_messages.

    CONSTANTS mc_zip_suffix TYPE string VALUE '.zip'.
    CONSTANTS mc_bin_len    TYPE i      VALUE 1024.

    TYPES ty_binary TYPE x LENGTH 1024.
    TYPES tt_binary TYPE STANDARD TABLE OF ty_binary WITH DEFAULT KEY.

    DATA mo_transport_manager TYPE REF TO zcl_transport_manager.
    DATA mx_message           TYPE REF TO cx_root.

    METHODS get_client_seperator
      RETURNING VALUE(rv_seperator) TYPE string
      RAISING   zcx_transport_manager_message.

    METHODS read_client_file
      IMPORTING iv_file        TYPE string
      RETURNING VALUE(rv_data) TYPE xstring
      RAISING   zcx_transport_manager_message.

    METHODS write_client_file
      IMPORTING iv_file TYPE string
                iv_data TYPE xstring
      RAISING   zcx_transport_manager_message.

    METHODS run_download
      RAISING zcx_transport_manager_message.

    METHODS run_upload
      RAISING zcx_transport_manager_message.
ENDCLASS.


CLASS lcl_application IMPLEMENTATION.

  METHOD initialization.
    " Setup dynamic screen texts
    %_p_upload_%_app_%-text = mc_texts-upload.
    %_p_downld_%_app_%-text = mc_texts-download.
    %_p_trkorr_%_app_%-text = mc_texts-request.
    %_p_folder_%_app_%-text = mc_texts-folder.
    %_p_filenm_%_app_%-text = mc_texts-file.
    %_p_imprt_%_app_%-text  = mc_texts-import.
    %_p_pop_%_app_%-text    = mc_texts-populate.
    %_p_noimp_%_app_%-text  = mc_texts-no_imp.

    t01 = mc_texts-t01.
    t02 = mc_texts-t02.

    CONCATENATE sy-sysid 'K*' INTO p_trkorr.

    " Set default paths to desktop
    cl_gui_frontend_services=>get_desktop_directory( CHANGING   desktop_directory = p_folder
                                                     EXCEPTIONS OTHERS            = 1 ).
    cl_gui_frontend_services=>get_desktop_directory( CHANGING   desktop_directory = p_filenm
                                                     EXCEPTIONS OTHERS            = 1 ).
  ENDMETHOD.

  METHOD start_of_selection.
    TRY.
        mo_transport_manager = NEW #( ).

        CASE abap_true.
          WHEN p_downld.
            run_download( ).
          WHEN p_upload.
            run_upload( ).
        ENDCASE.

      CATCH cx_root INTO mx_message.
        WRITE / mx_message->get_text( ) COLOR COL_NEGATIVE.
        " If the failure carries tp stdout output, dump it for diagnostics
        IF mx_message IS INSTANCE OF zcx_transport_manager_message.
          DATA(lo_tm_msg) = CAST zcx_transport_manager_message( mx_message ).
          LOOP AT lo_tm_msg->mt_stdout ASSIGNING FIELD-SYMBOL(<fs_stdout>).
            WRITE / <fs_stdout>-line COLOR COL_NEGATIVE.
          ENDLOOP.
        ENDIF.
    ENDTRY.
  ENDMETHOD.

  METHOD run_download.
    DATA lv_zip      TYPE xstring.
    DATA lv_filename TYPE string.
    DATA lv_sep      TYPE string.

    IF p_trkorr IS INITIAL.
      MESSAGE mc_messages-request_must_be_provided TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF p_folder IS INITIAL.
      MESSAGE mc_messages-folder_must_be_provided TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " Delegate: pull the raw ZIP bytes from the server via the manager.
    lv_zip = mo_transport_manager->download_request( iv_request = p_trkorr ).

    " Compose local target filename: <folder>[<sep>]<TR>.zip
    lv_sep = get_client_seperator( ).
    IF substring( val = p_folder
                  off = strlen( p_folder ) - 1 ) = lv_sep.
      lv_filename = p_folder && p_trkorr.
    ELSE.
      lv_filename = p_folder && lv_sep && p_trkorr.
    ENDIF.
    lv_filename = lv_filename && mc_zip_suffix.

    write_client_file( iv_file = lv_filename
                       iv_data = lv_zip ).

    WRITE / mc_messages-download_ok COLOR COL_POSITIVE.
  ENDMETHOD.

  METHOD run_upload.
    DATA lv_zip     TYPE xstring.
    DATA lv_request TYPE trkorr.

    IF p_filenm IS INITIAL.
      MESSAGE mc_messages-file_name_must_be_provided TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " Read the ZIP off the user's PC, then hand the bytes to the manager.
    lv_zip = read_client_file( p_filenm ).

    mo_transport_manager->upload_request( EXPORTING iv_zip     = lv_zip
                                          IMPORTING ev_request = lv_request ).
    WRITE / mc_messages-upload_ok COLOR COL_POSITIVE.

    CASE abap_true.
      WHEN p_imprt.
        mo_transport_manager->import_request( iv_request = lv_request ).
        WRITE / mc_messages-import_ok COLOR COL_POSITIVE.
      WHEN p_pop.
        mo_transport_manager->populate_request_tables( iv_request = lv_request ).
        WRITE / mc_messages-populate_ok COLOR COL_POSITIVE.
    ENDCASE.
  ENDMETHOD.

  METHOD at_selection_screen_output.
    " Dynamic UI: Hide/Show fields based on Radio Button selection
    LOOP AT SCREEN.
      IF p_downld = abap_true.
        IF screen-group1 = mc_modif_ids-download.
          screen-required = 2.
        ELSEIF screen-group1 = mc_modif_ids-upload.
          screen-active = 0.
        ENDIF.
      ELSE.
        IF screen-group1 = mc_modif_ids-download.
          screen-active = 0.
        ELSEIF screen-group1 = mc_modif_ids-upload.
          screen-required = 2.
        ENDIF.
      ENDIF.
      MODIFY SCREEN.
    ENDLOOP.
  ENDMETHOD.

  METHOD at_selection_screen_for_file.
    DATA lt_filetable TYPE filetable.
    DATA lv_rc        TYPE sy-subrc.

    cl_gui_frontend_services=>file_open_dialog( EXPORTING  default_filename = '*.zip'
                                                           file_filter      = |ZIP Files (*.zip)\|*.zip\||
                                                CHANGING   file_table       = lt_filetable
                                                           rc               = lv_rc
                                                EXCEPTIONS OTHERS           = 1 ).
    p_filenm = VALUE #( lt_filetable[ 1 ] OPTIONAL ).
  ENDMETHOD.

  METHOD at_selection_screen_for_folder.
    cl_gui_frontend_services=>directory_browse( CHANGING   selected_folder = p_folder
                                                EXCEPTIONS OTHERS          = 1 ).
  ENDMETHOD.

  METHOD at_selection_screen_for_trkorr.
    DATA ls_selection TYPE trwbo_selection.
    DATA ls_selected  TYPE trwbo_request_header.

    ls_selection-reqstatus = 'R'. " Released only

    CALL FUNCTION 'TR_PRESENT_REQUESTS_SEL_POPUP'
      EXPORTING iv_organizer_type   = ''
                is_selection        = ls_selection
      IMPORTING es_selected_request = ls_selected.

    IF ls_selected-trkorr IS NOT INITIAL.
      p_trkorr = ls_selected-trkorr.
    ENDIF.
  ENDMETHOD.

  METHOD get_client_seperator.
    DATA lv_seperator TYPE c LENGTH 1.

    cl_gui_frontend_services=>get_file_separator(
      CHANGING file_separator = lv_seperator ).
    rv_seperator = lv_seperator.
  ENDMETHOD.

  METHOD read_client_file.
    DATA lt_bin TYPE tt_binary.
    DATA lv_len TYPE i.

    cl_gui_frontend_services=>gui_upload( EXPORTING  filename   = iv_file
                                                     filetype   = 'BIN'
                                          IMPORTING  filelength = lv_len
                                          CHANGING   data_tab   = lt_bin
                                          EXCEPTIONS OTHERS     = 1 ).
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING  input_length = lv_len
      IMPORTING  buffer       = rv_data
      TABLES     binary_tab   = lt_bin
      EXCEPTIONS OTHERS       = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.
  ENDMETHOD.

  METHOD write_client_file.
    DATA lv_len TYPE i.
    DATA lt_bin TYPE tt_binary.

    CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
      EXPORTING  buffer        = iv_data
      IMPORTING  output_length = lv_len
      TABLES     binary_tab    = lt_bin
      EXCEPTIONS OTHERS        = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    cl_gui_frontend_services=>gui_download( EXPORTING  bin_filesize = lv_len
                                                       filename     = iv_file
                                                       filetype     = 'BIN'
                                            CHANGING   data_tab     = lt_bin
                                            EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.


" -----------------------------------------------------------------------
" Global Execution Logic
" -----------------------------------------------------------------------
DATA lo_app TYPE REF TO lcl_application.

LOAD-OF-PROGRAM.
  lo_app = NEW lcl_application( ).

INITIALIZATION.
  lo_app->initialization( ).

AT SELECTION-SCREEN OUTPUT.
  lo_app->at_selection_screen_output( ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_filenm.
  lo_app->at_selection_screen_for_file( ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_folder.
  lo_app->at_selection_screen_for_folder( ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_trkorr.
  lo_app->at_selection_screen_for_trkorr( ).

START-OF-SELECTION.
  lo_app->start_of_selection( ).
