" -----------------------------------------------------------------------
" Server-side file manager: reads/writes files under DIR_TRANS on the
" application server. This is the only file medium used by
" ZCL_TRANSPORT_MANAGER — the frontend (client PC) implementation from
" the legacy report is not needed for a class that operates on xstring.
" -----------------------------------------------------------------------
CLASS lcl_server_file_manager DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_file_manager.

    METHODS constructor
      RAISING zcx_transport_manager_message.

  PRIVATE SECTION.
    DATA mv_transdir TYPE text255.
ENDCLASS.


CLASS lcl_server_file_manager IMPLEMENTATION.

  METHOD constructor.
    CALL FUNCTION 'RSPO_R_SAPGPARAM'
      EXPORTING  name   = 'DIR_TRANS'
      IMPORTING  value  = mv_transdir
      EXCEPTIONS OTHERS = 1.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.
  ENDMETHOD.

  METHOD lif_file_manager~get_seperator.
    rv_seperator = COND #( WHEN sy-opsys CP '*Windows*' THEN '\' ELSE '/' ).
  ENDMETHOD.

  METHOD lif_file_manager~read.
    DATA lv_file      TYPE string.
    DATA lv_seperator TYPE string.

    lv_seperator = lif_file_manager~get_seperator( ).
    CONCATENATE mv_transdir iv_file INTO lv_file SEPARATED BY lv_seperator.

    OPEN DATASET lv_file FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    READ DATASET lv_file INTO rv_data.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CLOSE DATASET lv_file.
  ENDMETHOD.

  METHOD lif_file_manager~write.
    DATA lv_file      TYPE string.
    DATA lv_seperator TYPE string.

    lv_seperator = lif_file_manager~get_seperator( ).
    CONCATENATE mv_transdir iv_file INTO lv_file SEPARATED BY lv_seperator.

    OPEN DATASET lv_file FOR OUTPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    TRANSFER iv_data TO lv_file.
    IF sy-subrc <> 0.
      zcx_transport_manager_message=>raise_syst( ).
    ENDIF.

    CLOSE DATASET lv_file.
  ENDMETHOD.

ENDCLASS.
