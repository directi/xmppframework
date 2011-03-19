//
//  XMPPSocketTransport.h
//  iPhoneXMPP
//
//  Created by Chaitanya Gupta on 16/03/11.
//  Copyright 2011 Directi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPTransportProtocol.h"
#import "MulticastDelegate.h"

#if TARGET_OS_IPHONE
    #import "DDXML.h"
#endif

@class AsyncSocket;
@class XMPPParser;
@class XMPPJID;

// Define the debugging state
#define DEBUG_SEND      YES
#define DEBUG_RECV_PRE  NO  // Prints data before going to xmpp parser
#define DEBUG_RECV_POST YES   // Prints data as it comes out of xmpp parser

#define DDLogSend(format, ...)     do{ if(DEBUG_SEND)      NSLog((format), ##__VA_ARGS__); }while(0)
#define DDLogRecvPre(format, ...)  do{ if(DEBUG_RECV_PRE)  NSLog((format), ##__VA_ARGS__); }while(0)
#define DDLogRecvPost(format, ...) do{ if(DEBUG_RECV_POST) NSLog((format), ##__VA_ARGS__); }while(0)

// Define the various timeouts (in seconds) for retreiving various parts of the XML stream
#define TIMEOUT_WRITE         10
#define TIMEOUT_READ_START    10
#define TIMEOUT_READ_STREAM   -1

// Define the various tags we'll use to differentiate what it is we're currently reading or writing
#define TAG_WRITE_START        -100 // Must be outside UInt16 range
#define TAG_WRITE_STREAM       -101 // Must be outside UInt16 range
#define TAG_WRITE_SYNCHRONOUS  -102 // Must be outside UInt16 range

#define TAG_READ_START       200
#define TAG_READ_STREAM      201


#if TARGET_OS_IPHONE
#define DEFAULT_KEEPALIVE_INTERVAL 120.0 // 2 Minutes
#else
#define DEFAULT_KEEPALIVE_INTERVAL 300.0 // 5 Minutes
#endif

enum xmppSocketState {
    XMPP_SOCKET_DISCONNECTED,
    XMPP_SOCKET_OPENING,
    XMPP_SOCKET_NEGOTIATING,
    XMPP_SOCKET_CONNECTED,
    XMPP_SOCKET_RESTARTING
};

@interface XMPPSocketTransport : NSObject <XMPPTransportProtocol> {
    MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
    AsyncSocket *asyncSocket;
    XMPPParser *parser;
    
    enum xmppSocketState state;
    NSString *host;
    UInt16 port;
    XMPPJID *myJID;
    
    BOOL isSecure;
    
    int numberOfBytesSent;
    int numberOfBytesReceived;

    NSXMLElement *rootElement;
    
    // P2P stuff
    BOOL isP2P;
    BOOL isP2PRecipient;
    XMPPJID *remoteJID;
}
@property (readonly) NSString *host;
@property (retain) XMPPJID *myJID;
@property (retain) XMPPJID *remoteJID;
@property (readonly) BOOL isP2PRecipient;

- (id)initWithHost:(NSString *)host port:(UInt16)port;
- (id)initP2PWithHost:(NSString *)host port:(UInt16)port;
- (id)initP2PWithSocket:(AsyncSocket *)socket;

- (void)addDelegate:(id)delegate;
- (void)removeDelegate:(id)delegate;
- (BOOL)connect:(NSError **)errPtr;
- (void)disconnect;
- (void)restartStream;
- (float)serverXmppStreamVersionNumber;
- (BOOL)sendStanza:(NSXMLElement *)stanza;
- (BOOL)sendStanzaWithString:(NSString *)string;

- (void)secure;
- (BOOL)isSecure;

@end
