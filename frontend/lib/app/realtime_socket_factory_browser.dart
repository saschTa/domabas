import '../data/realtime/datasources/realtime_socket_attempt.dart';
import '../data/realtime/datasources/realtime_socket_factory_web.dart';

RealtimeSocketAttempt createRealtimeSocketAttempt(Uri endpoint) =>
    createSocketAttempt(endpoint);
