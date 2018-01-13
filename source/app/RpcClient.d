




module kissrpc.RpcClient;

import kiss.net.TcpStreamClient;
import kissrpc.RpcCodec;
import kissrpc.RpcConstant;
import kissrpc.RpcStream;
import kiss.event.loop;



import core.sync.semaphore;
import std.traits;
import core.thread;
import std.stdio;
import std.experimental.logger.core;



alias RpcConnectCb = void function(RpcClient client);


class RpcClient {
public:
    this(EventLoop loop, string host, ushort port, RpcEventHandler handler = null, ubyte protocol = RpcProtocol.FlatBuffer, ubyte compress = RpcCompress.None) {
        _loop = loop;
        _host = host;
        _port = port;
        _protocol = protocol;
        _compress = compress;
        _clientSeqId = 0;
        _semaphore = new Semaphore();
        _rpcStream = RpcStream.createClient(_loop, handler, 0);
    }
    void start() {
        _loop.join();
    }
    void stop() {
        _rpcStream.close();
    }
    void connect() {
        _rpcStream.connect(_host, _port);
    }
    void setConnectHandle(RpcConnectCb cback){
        _rpcStream.setConnectHandle((){
            cback(this);
        });
    }
    RpcResponseBody call(T)(string functionName, T param, ubyte[] exData) {
        RpcResponseBody ret;
        RpcHeadData head;
        RpcContentData content;
        ubyte code = initHeadBody!(T)(functionName, param, exData, head, content);
        ret.code = code;
        if (code != RpcProcCode.Success) {
            ret.msg = "function call encode failed";
        }
        else {
            void callBack(RpcResponseBody response, ubyte[] data, ubyte protocol) {
                ret.code = response.code;
                ret.msg = response.msg;
                ret.exData = response.exData;
                _semaphore.notify();
            }
            _rpcStream.addRequestCallback(head.clientSeqId, &callBack);
            _rpcStream.writeRpcData(head, content);
            _semaphore.wait(); 
        }
        _rpcStream.removeRequestCallback(head.clientSeqId);
        return ret;
    }
    RpcResponseBody call(T,R)(string functionName, T param, ref R r,ubyte[] exData) {
        RpcResponseBody ret;
        RpcHeadData head;
        RpcContentData content;
        ubyte code = initHeadBody!(T)(functionName, param, exData, head, content);
        ret.code = code;
        if (code != RpcProcCode.Success) {
            ret.msg = "function call encode failed";
        }
        else {
            void callBack(RpcResponseBody response, ubyte[] data, ubyte protocol) {
                ret.code = response.code;
                ret.msg = response.msg;
                ret.exData = response.exData;
                if (ret.code == RpcProcCode.Success) {
                    ret.code = RpcCodec.decodeBuffer!(R)(data, protocol, r);
                }
                _semaphore.notify();
            }
            _rpcStream.addRequestCallback(head.clientSeqId, &callBack);
            _rpcStream.writeRpcData(head, content);
            _semaphore.wait(); 
        }
        _rpcStream.removeRequestCallback(head.clientSeqId);
        return ret;
    }
    void call(T,R)(string functionName, T param, void delegate(RpcResponseBody response, R r) func, ubyte[] exData) {
        RpcHeadData head;
        RpcContentData content;
        ubyte code = initHeadBody!(T)(functionName, param, exData, head, content);
        if (code != RpcProcCode.Success) {
            RpcResponseBody response;
            response.code = code;
            response.msg = "function call encode failed";
            R r;
            func(response, r);
            _rpcStream.removeRequestCallback(head.clientSeqId);
        }
        else {
            void callBack(RpcResponseBody response, ubyte[] data, ubyte protocol) {
                if (response.code == RpcProcCode.Success) {
                    R r;
                    response.code = RpcCodec.decodeBuffer!(R)(data, protocol, r);
                    func(response, r);
                    _rpcStream.removeRequestCallback(head.clientSeqId);
                }
            }
            _rpcStream.addRequestCallback(head.clientSeqId, &callBack);
            _rpcStream.writeRpcData(head, content);
        }
    }
    void call(T)(string functionName, T param, void delegate(RpcResponseBody response) func, ubyte[] exData) {
        RpcHeadData head;
        RpcContentData content;
        ubyte code = initHeadBody!(T)(functionName, param, exData, head, content);
        if (code != RpcProcCode.Success) {
            RpcResponseBody response;
            response.code = code;
            response.msg = "function call encode failed";
            func(response);
            _rpcStream.removeRequestCallback(head.clientSeqId);
        }
        else {
            void callBack(RpcResponseBody response, ubyte[] data, ubyte protocol) {
                if (response.code == RpcProcCode.Success) {
                    func(response);
                    _rpcStream.removeRequestCallback(head.clientSeqId);
                }
            }
            _rpcStream.writeRpcData(head, content, &callBack);
        }
    }
private:
    ubyte initHeadBody(T)(string functionName, T param, ubyte[] exData, ref RpcHeadData head, ref RpcContentData content) {
        ubyte code = RpcCodec.encodeBuffer!(T)(param, _protocol, content.data);
        if (code != RpcProcCode.Success)
            return code;

        head.rpcVersion = RPC_VERSION;
        head.key = RPC_KEY;
        head.secret = RPC_SECRET;
        head.compress = _compress;
        head.protocol = _protocol;
        head.msgLen = cast(ubyte)functionName.length;
        synchronized(this) {
            head.clientSeqId = _clientSeqId++;
        }
        if (exData !is null) {
            head.exDataLen = cast(ushort)exData.length;
            content.exData = exData.dup;
        }
        content.msg = functionName;
        head.dataLen = cast(ushort)content.data.length;

        return RpcProcCode.Success;
    }
public:
    RpcStream _rpcStream;
private:
    string _host;
    ushort _port;
    ulong _clientSeqId;
    EventLoop _loop;
    ubyte _protocol;
    ubyte _compress;
    Semaphore _semaphore;
}   