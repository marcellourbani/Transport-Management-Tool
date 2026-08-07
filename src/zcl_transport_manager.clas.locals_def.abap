" -----------------------------------------------------------------------
" Local interface visible to the main class definition (private DATA
" member type). Kept in locals_def because the compiler needs the
" type to be defined before the main class definition is processed.
" -----------------------------------------------------------------------
INTERFACE lif_file_manager.

  METHODS read
    IMPORTING iv_file        TYPE string
    RETURNING VALUE(rv_data) TYPE xstring
    RAISING   zcx_transport_manager_message.

  METHODS write
    IMPORTING iv_file TYPE string
              iv_data TYPE xstring
    RAISING   zcx_transport_manager_message.

  METHODS get_seperator
    RETURNING VALUE(rv_seperator) TYPE string
    RAISING   zcx_transport_manager_message.

ENDINTERFACE.
