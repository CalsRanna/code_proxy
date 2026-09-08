import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_proxy/service/proxy_server/proxy_server_request_cancellation.dart';

/// Observes socket EOF before HttpServer's paused request stream can hide it.
/// HTTP parsing, response framing and socket backpressure stay with dart:io.
class ProxyServerClientConnections extends Stream<Socket>
    implements ServerSocket {
  final ServerSocket _server;
  final _connections = <(String, int), ProxyServerRequestCancellation>{};

  ProxyServerClientConnections(this._server);

  /// Links only the current request; keep-alive requests get separate tokens.
  void Function() track(
    HttpConnectionInfo info,
    ProxyServerRequestCancellation request,
  ) {
    final connection =
        _connections[(info.remoteAddress.address, info.remotePort)];
    if (connection == null) {
      request.cancel(const ProxyServerRequestCancelled('Client disconnected'));
      return () {};
    }
    return connection.onCancel(() => request.cancel(connection.reason!));
  }

  Socket _trackSocket(Socket socket) {
    final key = (socket.remoteAddress.address, socket.remotePort);
    final connection = ProxyServerRequestCancellation();
    _connections[key] = connection;
    void disconnected() {
      if (connection.isCancelled) return;
      _connections.remove(key);
      connection.cancel(
        const ProxyServerRequestCancelled('Client disconnected'),
      );
    }

    return _ObservedSocket(socket, disconnected);
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _server
      .map(_trackSocket)
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  InternetAddress get address => _server.address;

  @override
  int get port => _server.port;

  @override
  Future<ServerSocket> close() => _server.close();
}

class _ObservedSocket extends StreamView<Uint8List> implements Socket {
  final Socket _socket;
  final void Function() _disconnected;

  _ObservedSocket(this._socket, this._disconnected)
    : super(
        _socket.transform(
          StreamTransformer.fromHandlers(
            handleError: (error, stack, sink) {
              _disconnected();
              sink.addError(error, stack);
            },
            handleDone: (sink) {
              _disconnected();
              sink.close();
            },
          ),
        ),
      );

  @override
  void destroy() {
    _disconnected();
    _socket.destroy();
  }

  @override
  InternetAddress get address => _socket.address;

  @override
  int get port => _socket.port;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future close() => _socket.close();

  @override
  Future get done => _socket.done;
}
