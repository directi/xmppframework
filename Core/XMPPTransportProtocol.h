//
//  XMPPTransportProtocol.h
//  iPhoneXMPP
//
//  Created by Chaitanya Gupta on 16/03/11.
//  Copyright 2011 Directi. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NSXMLElement;
@class XMPPJID;

@protocol XMPPTransportProtocol

- (void)addDelegate:(id)delegate;
- (void)removeDelegate:(id)delegate;
- (void)setMyJID:(XMPPJID *)jid;
- (BOOL)connect:(NSError **)errPtr;
- (BOOL)disconnect;
- (void)restartStream;
- (BOOL)sendStanza:(NSXMLElement *)stanza;
- (BOOL)sendStanzaWithString:(NSString *)string;
@optional
- (BOOL)secure;

@end


@protocol XMPPTransportDelegate

@optional
- (void)transportWillConnect:(id <XMPPTransportProtocol>)transport;
- (void)transportDidStartNegotiation:(id <XMPPTransportProtocol>)transport;
- (void)transportDidConnect:(id <XMPPTransportProtocol>)transport;
- (void)transportDidDisconnect:(id <XMPPTransportProtocol>)transport;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveStanza:(NSXMLElement *)stanza;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveError:(id)error;
- (void)transportDidSecure:(id <XMPPTransportProtocol>)transport;

@end
