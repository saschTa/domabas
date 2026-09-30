import '../data/realtime/datasources/realtime_socket_attempt.dart';
import '../data/realtime/datasources/realtime_socket_factory_native.dart';
import 'native_http_client_factory.dart';

RealtimeSocketAttempt createRealtimeSocketAttempt(Uri endpoint) =>
    createSocketAttempt(endpoint, clientFactory: createNativeHttpClient);
