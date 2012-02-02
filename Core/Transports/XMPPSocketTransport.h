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
@class RFSRVResolver;

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
    XMPP_SOCKET_RESOLVING_SRV,
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
    
    // keep alive
    NSTimeInterval keepAliveInterval;
	NSTimer *keepAliveTimer;
    
    // P2P stuff
    BOOL isP2P;
    BOOL isP2PRecipient;
    XMPPJID *remoteJID;
    
    // SRV resolver
    RFSRVResolver *srvResolver;
	NSArray *srvResults;
	NSUInteger srvResultsIndex;
}
@property (nonatomic, readonly, copy) NSString *host;
@property (nonatomic, retain) XMPPJID *myJID;
@property (nonatomic, retain) XMPPJID *remoteJID;
@property (nonatomic, readonly) BOOL isP2PRecipient;

- (id)init;
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
