CLASS zcx_transport_http DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    CONSTANTS:
      BEGIN OF mc_general_error,
        msgid TYPE symsgid      VALUE '00',
        msgno TYPE symsgno      VALUE '001',
        attr1 TYPE scx_attrname VALUE 'MSGV1',
        attr2 TYPE scx_attrname VALUE 'MSGV2',
        attr3 TYPE scx_attrname VALUE 'MSGV3',
        attr4 TYPE scx_attrname VALUE 'MSGV4',
      END OF mc_general_error.

    " Field: free-text error message
    DATA mv_message     TYPE string READ-ONLY.
    " Field: HTTP status / return code to send back to the caller
    DATA mv_return_code TYPE i      READ-ONLY.

    " MSGV parts are needed by if_t100_dyn_msg
    DATA msgv1 TYPE msgv1.
    DATA msgv2 TYPE msgv2.
    DATA msgv3 TYPE msgv3.
    DATA msgv4 TYPE msgv4.

    METHODS constructor
      IMPORTING textid         LIKE if_t100_message=>t100key OPTIONAL
                !previous      LIKE previous                 OPTIONAL
                iv_message     TYPE string                   OPTIONAL
                iv_return_code TYPE i                        OPTIONAL.

    CLASS-METHODS raise
      IMPORTING iv_message     TYPE string
                iv_return_code TYPE i
                !previous      TYPE REF TO cx_root OPTIONAL
      RAISING   zcx_transport_http.

ENDCLASS.


CLASS zcx_transport_http IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    DATA lv_message TYPE c LENGTH 200.

    super->constructor( previous = previous ).

    me->mv_message     = iv_message.
    me->mv_return_code = iv_return_code.

    lv_message = iv_message.
    me->msgv1  = lv_message+000(50).
    me->msgv2  = lv_message+050(50).
    me->msgv3  = lv_message+100(50).
    me->msgv4  = lv_message+150(50).

    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

  METHOD raise.
    RAISE EXCEPTION TYPE zcx_transport_http
      EXPORTING textid         = zcx_transport_http=>mc_general_error
                iv_message     = iv_message
                iv_return_code = iv_return_code
                previous       = previous.
  ENDMETHOD.

ENDCLASS.
