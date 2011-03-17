//
//  XMPPTransportProtocol.h
//  iPhoneXMPP
//
//  Created by Chaitanya Gupta on 16/03/11.
//  Copyright 2011 Directi. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol XMPPTransportProtocol

- (void)setDelegate:(id)delegate;
- (BOOL)connect:(NSError *)errPtr;
- (BOOL)disconnect;
- (BOOL)sendStanza:(NSXMLElement *)stanza;

@optional
- (BOOL)secure;
@end


@protocol XMPPTransportDelegate
- (void)transportDidConnect:(id <XMPPTransportProtocol>)transport;
- (void)transportDidDisconnect:(id <XMPPTransportProtocol>)transport;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveStanza:(NSXMLElement *)stanza;
- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveError:(id)error;

@optional
- (void)transportDidSecure:(id <XMPPTransportProtocol>)transport;
@end
