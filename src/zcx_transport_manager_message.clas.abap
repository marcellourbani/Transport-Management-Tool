CLASS zcx_transport_manager_message DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    TYPES tt_stdout TYPE STANDARD TABLE OF tpstdout WITH DEFAULT KEY.

    CONSTANTS:
      BEGIN OF mc_general_error,
        msgid TYPE symsgid      VALUE '00',
        msgno TYPE symsgno      VALUE '001',
        attr1 TYPE scx_attrname VALUE 'MSGV1',
        attr2 TYPE scx_attrname VALUE 'MSGV2',
        attr3 TYPE scx_attrname VALUE 'MSGV3',
        attr4 TYPE scx_attrname VALUE 'MSGV4',
      END OF mc_general_error.

    DATA msgv1     TYPE msgv1.
    DATA msgv2     TYPE msgv2.
    DATA msgv3     TYPE msgv3.
    DATA msgv4     TYPE msgv4.
    DATA mt_stdout TYPE tt_stdout.

    METHODS constructor
      IMPORTING textid    LIKE if_t100_message=>t100key OPTIONAL
                !previous LIKE previous                 OPTIONAL
                msgv1     TYPE msgv1                    OPTIONAL
                msgv2     TYPE msgv2                    OPTIONAL
                msgv3     TYPE msgv3                    OPTIONAL
                msgv4     TYPE msgv4                    OPTIONAL.

    CLASS-METHODS raise
      IMPORTING iv_message TYPE string
      RAISING   zcx_transport_manager_message.

    CLASS-METHODS raise_syst
      RAISING zcx_transport_manager_message.

    CLASS-METHODS raise_tp_failure
      IMPORTING iv_message TYPE string
                it_stdout  TYPE tt_stdout
      RAISING   zcx_transport_manager_message.

ENDCLASS.


CLASS zcx_transport_manager_message IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->msgv1 = msgv1.
    me->msgv2 = msgv2.
    me->msgv3 = msgv3.
    me->msgv4 = msgv4.
    CLEAR me->textid.
    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.
  ENDMETHOD.

  METHOD raise.
    DATA lv_message TYPE c LENGTH 200.

    lv_message = iv_message.

    RAISE EXCEPTION TYPE zcx_transport_manager_message
      EXPORTING textid = zcx_transport_manager_message=>mc_general_error
                msgv1  = lv_message+000(50)
                msgv2  = lv_message+050(50)
                msgv3  = lv_message+100(50)
                msgv4  = lv_message+150(50).
  ENDMETHOD.

  METHOD raise_syst.
    DATA lv_message TYPE c LENGTH 200.

    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
            INTO lv_message
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.

    RAISE EXCEPTION TYPE zcx_transport_manager_message
      EXPORTING textid = zcx_transport_manager_message=>mc_general_error
                msgv1  = lv_message+000(50)
                msgv2  = lv_message+050(50)
                msgv3  = lv_message+100(50)
                msgv4  = lv_message+150(50).
  ENDMETHOD.

  METHOD raise_tp_failure.
    DATA lv_message TYPE c LENGTH 200.
    DATA lo_ex      TYPE REF TO zcx_transport_manager_message.

    lv_message = iv_message.

    lo_ex = NEW zcx_transport_manager_message(
      textid = zcx_transport_manager_message=>mc_general_error
      msgv1  = lv_message+000(50)
      msgv2  = lv_message+050(50)
      msgv3  = lv_message+100(50)
      msgv4  = lv_message+150(50) ).

    lo_ex->mt_stdout = it_stdout.

    RAISE EXCEPTION lo_ex.
  ENDMETHOD.

ENDCLASS.
