set pagination off
set confirm off
set print thread-events off
starti
watch *(void**)0x9088240
commands
silent
printf "DOCUMENT_POINTER_CHANGE thread=%d: ", $_thread
x/gx 0x9088240
bt 10
continue
end
break *0x1cf9a20
commands
silent
printf "EXT_DOC_CALLBACK thread=%d document=", $_thread
x/gx 0x9088240
bt 8
continue
end
continue
printf "FINAL_STATE\n"
info program
x/gx 0x9088240
bt 18
thread apply all bt 5
info registers rbx rdi rip
info sharedlibrary
