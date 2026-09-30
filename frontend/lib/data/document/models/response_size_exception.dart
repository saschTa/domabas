import 'package:http/http.dart' as http;

final class ResponseSizeException extends http.ClientException {
  ResponseSizeException() : super('Response exceeds the supported size.');
}
