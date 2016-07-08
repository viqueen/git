#ifndef UNIX_SOCKET_H
#define UNIX_SOCKET_H

#ifndef NO_UNIX_SOCKETS

int unix_stream_connect(const char *path);
int unix_stream_listen(const char *path);

#else

static inline int unix_stream_connect(const char *path)
{
	errno = ENOSYS;
	return -1;
}

static inline int unix_stream_listen(const char *path)
{
	errno = ENOSYS;
	return -1;
}

#endif

#endif /* UNIX_SOCKET_H */
