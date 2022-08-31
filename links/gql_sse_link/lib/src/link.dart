import "dart:async";
import "dart:convert";

import "package:flutter_client_sse/flutter_client_sse.dart";
import "package:gql_exec/gql_exec.dart";
import "package:gql_link/gql_link.dart";
import "package:gql_sse_link/gql_sse_link.dart";
import "package:http/http.dart" as http;
import "package:http2/http2.dart";
import "package:meta/meta.dart";
import "package:rxdart/rxdart.dart";
import "package:uuid/uuid.dart";
import "package:web_socket_channel/status.dart" as websocket_status;
import "package:web_socket_channel/web_socket_channel.dart";

final uuid = Uuid();

typedef HttpResponseDecoder = FutureOr<Map<String, dynamic>>? Function(
    http.Response message);

@immutable
class RequestId extends ContextEntry {
  final String id;

  const RequestId(this.id);

  @override
  List<Object> get fieldsForEquality => [id];
}

/// A Universal WebSocket [Link] implementation to support the
/// WebSocket-GraphQL transport.
/// It supports subscriptions, query and mutation operations as well.
///
/// NOTE: the actual socket connection will only get established after
/// a [Request] is handled by this [SSELink].
class SSELink extends Link {
  ClientTransportConnection? transport;

  /// Endpoint of the GraphQL service
  final Uri uri;

  /// Default HTTP headers
  final Map<String, String> defaultHeaders;

  // Current active subscriptions
  final _requests = <Request>[];

  // subscriptions that need to be re-initialized after channel reconnect
  final _reConnectRequests = <Request>[];

  /// Serializer used to serialize request
  final RequestSerializer serializer;

  /// Parser used to parse response
  final ResponseParser parser;

  /// A function that decodes the incoming http response to `Map<String, dynamic>`,
  /// the decoded map will be then passes to the `RequestSerializer`.
  /// It is recommended for performance to decode the response using `compute` function.
  /// ```
  /// httpResponseDecoder : (http.Response httpResponse) async => await compute(jsonDecode, httpResponse.body) as Map<String, dynamic>,
  /// ```
  HttpResponseDecoder httpResponseDecoder;

  static Map<String, dynamic>? _defaultHttpResponseDecoder(
          http.Response httpResponse) =>
      json.decode(
        utf8.decode(
          httpResponse.bodyBytes,
        ),
      ) as Map<String, dynamic>?;

  http.Client? _httpClient;

  /// Automatically recreate the channel when connection is lost,
  /// and re send all active subscriptions. `true` by default.
  bool autoReconnect;

  Timer? _reconnectTimer;

  /// The interval between reconnects, the default value is 10 seconds.
  final Duration reconnectInterval;

  // /// Payload to be sent with the connection_init request
  // /// Must be able to `json.encode(initialPayload)`.
  // final dynamic initialPayload;

  // /// The duration after which the connection is considered unstable,
  // /// because no keep alive message was received from the server in the given time-frame.
  // /// The connection to the server will be closed.
  // /// If the value is null this is ignored, By default this is null.
  // final Duration? inactivityTimeout;

  // /// Tracks state of the connection state.
  // final BehaviorSubject<ConnectionState> _connectionStateController =
  //     BehaviorSubject<ConnectionState>.seeded(ConnectionState.closed);

  // final StreamController<GraphQLSocketMessage> _messagesController =
  //     StreamController<GraphQLSocketMessage>.broadcast();
  // StreamSubscription<ConnectionKeepAlive>? _keepAliveSubscription;

  /// Completes when the [SSELink] is disposed.
  /// Non-null when the Link is closing or already closed with [_close].
  Completer<void>? _disposedCompleter;

  /// true when the [SSELink] can't send any more messages.
  /// This happends after calling [dispose] or when [autoReconnect] is false
  /// and the web socket disconnected.
  bool get isDisabled => _disposedCompleter != null;

  // /// A stream that notifies about changes of the current connection state.
  // Stream<ConnectionState> get connectionStateStream =>
  //     _connectionStateController.stream;

  /// Initialize the [SSELink] with a [uri].
  /// You can customize the headers & protocols by passing [channelGenerator],
  /// if [channelGenerator] is passed, [uri] must be null.
  /// [channelGenerator] is a function that returns [WebSocketChannel] or [IOWebSocketChannel] or [HtmlWebSocketChannel].
  /// You can also pass custom [RequestSerializer serializer] & [ResponseParser parser].
  /// Also [initialPayload] to be passed with the first request to the GraphQL server.
  SSELink(
    String uri, {
    this.defaultHeaders = const {},
    http.Client? httpClient,
    this.autoReconnect = true,
    this.reconnectInterval = const Duration(seconds: 10),
    this.serializer = const RequestSerializer(),
    this.parser = const ResponseParser(),
    this.httpResponseDecoder = _defaultHttpResponseDecoder,
    // this.inactivityTimeout,
  }) : uri = Uri.parse(uri) {
    _httpClient = httpClient ?? http.Client();
  }

  @override
  Stream<Response> request(Request request, [forward]) async* {
    final String id = uuid.v4();
    final requestWithContext = request.withContextEntry<RequestId>(
      RequestId(id),
    );
    _requests.add(requestWithContext);

    final headers = {
      "Accept": "text/event-stream",
      "Cache-Control": "no-cache",
      ...defaultHeaders,
    };

    final stream = SSEClient.subscribeToSSE(
        url: uri
            .replace(queryParameters: serializer.serializeRequest(request))
            .toString(),
        header: headers);

    // plain event
    await for (final message in stream) {
      if (message.data != null) {
        final data =
            jsonDecode(message.data!) as Map<String, Map<String, dynamic>>;
        final response = parser.parseResponse(data);
        yield Response(
          data: response.data,
          errors: response.errors,
          response: response.response,
        );
      }
    }
  }
}
