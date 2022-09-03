import "package:gql_link/gql_link.dart";
import "package:gql_sse_link/gql_sse_link.dart";

void main() {
  // ignore: unused_local_variable
  final link = Link.from([
    // SomeLink(),
    SSELink("http://localhost:5000/graphql"),
  ]);
}
