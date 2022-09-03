import "package:gql_exec/gql_exec.dart";
import "package:gql_link/gql_link.dart";
import "package:gql_sse_link/gql_sse_link.dart";
import "package:meta/meta.dart";

/// Exception occurring when response parsing fails
@immutable
class SSELinkParserException extends ResponseFormatException {
  final GraphQLSocketMessage message;

  const SSELinkParserException({
    Object? originalException,
    StackTrace? originalStackTrace,
    required this.message,
  }) : super(
          originalException: originalException,
          originalStackTrace: originalStackTrace,
        );
}

/// Exception occurring when network fails
/// or parsed response is missing both `data` and `errors`
@immutable
class SSELinkServerException extends ServerException {
  final GraphQLSocketMessage? requestMessage;

  const SSELinkServerException({
    Object? originalException,
    StackTrace? originalStackTrace,
    Response? parsedResponse,
    this.requestMessage,
  }) : super(
          originalException: originalException,
          originalStackTrace: originalStackTrace,
          parsedResponse: parsedResponse,
        );
}
