;----------------------------------------------------------------------
; Strings
;----------------------------------------------------------------------

str_header:
;.db '\n', '\n', '\r', "= MSF time code receiver =", '\n', '\n', '\r', 0, 0
;.db "MSF", '\n', 0, 0

str_waiting_for_sync:
;.db "W3AM", '\n', 0

str_sanity_fail:
;.db "SF", 0, 0

str_sanity_ok:
;.db	"SOK", 0

str_times_consecutive:
;.db '\n', "CO", 0

str_times_not_consecutive:
;.db '\n', "NC", 0

str_cycle_complete:
;.db '\n', "OK", '\n', 0, 0

.db 0, 0
