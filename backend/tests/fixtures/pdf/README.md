# Password-protected PDF fixture

[`PasswordPDF`](password.go) creates a small PDF for tests that read
password-protected documents. It contains one page of caller-provided test text
and no external data.

The fixture uses PDF Standard Security Handler revision 2, with RC4 and MD5, to
check compatibility with older imported files. These algorithms are only part of
the test PDF format; Domabas does not use them for account passwords or stored
integration credentials.
