//
//  XMPPTransportProtocol.h
//  iPhoneXMPP
//
//  Created by Chaitanya Gupta on 16/03/11.
//  Copyright 2011 Directi. All rights reserved.
//

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
    #import "DDXML.h"
#endif

// Define the debugging state

#ifndef DEBUG_SEND
  #define DEBUG_SEND      NO
#endif

#ifndef DEBUG_RECV_PRE
  #define DEBUG_RECV_PRE  NO  // Prints data before going to xmpp parser
#endif

#ifndef DEBUG_RECV_POST
  #define DEBUG_RECV_POST NO   // Prints data as it comes out of xmpp parser
#endif

#define DDLogSend(format, ...)     do{ if(DEBUG_SEND)      NSLog((format), ##__VA_ARGS__); }while(0)
#define DDLogRecvPre(format, ...)  do{ if(DEBUG_RECV_PRE)  NSLog((format), ##__VA_ARGS__); }while(0)
#define DDLogRecvPost(format, ...) do{ if(DEBUG_RECV_POST) NSLog((format), ##__VA_ARGS__); }while(0)

@class XMPPJID;

@protocol XMPPTransportProtocol <NSObject>

- (void)addDelegate:(id)delegate;
- (void)removeDelegate:(id)delegate;
- (XMPPJID *)myJID;
- (void)setMyJID:(XMPPJID *)jid;
- (BOOL)connect:(NSError **)errPtr;
- (void)disconnect;
- (void)restartStream;
- (float)serverXmppStreamVersionNumber;
- (BOOL)sendStanza:(NSXMLElement *)stanza;
- (BOOL)sendStanzaWithString:(NSString *)string;
- (BOOL)supportsPause;

@optional
- (void)secure;
- (BOOL)isSecure;

// P2P
- (XMPPJID *)remoteJID;
- (void)setRemoteJID:(XMPPJID *)jid;
- (BOOL)isP2PRecipient;

- (BOOL)isPaused;
- (void)pause;
- (void)resume;

@end


@protocol XMPPTransportDelegate

@optional
- (void)transportWillConnect:(id <XMPPTransportProtocol>)transport;
- (void)transportDidStartNegotiation:(id <XMPPTransportProtocol>)transport;
- (void)transportDidConnect:(id <XMPPTransportProtocol>)transport;
- (void)transportWillDisconnect:(id <XMPPTransportProtocol>)transport;
- (void)transportWillDisconnect:(id<XMPPTransportProtocol>)transport withError:(NSError *)err;
- (void)transportDidDisconnect:(id <XMPPTransportProtocol>)transport;
- (void)transport:(id <XMPPTransportProtocol>)transport willSecureWithSettings:(NSDictionary *)settings;
- (void)transport:(id <XMPPTransportProtocol>)transport willSendStanza:(NSXMLElement *)stanza;
- (void)transport:(id <XMPPTransportProtocol>)transport didSendStanza:(NSXMLElement *)stanza;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveStanza:(NSXMLElement *)stanza;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveError:(id)error;
- (void)transportDidSecure:(id <XMPPTransportProtocol>)transport;

@end
