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
- (BOOL)open;
- (BOOL)close;
- (BOOL)sendStanza:(NSXMLElement *)stanza;

@optional
- (BOOL)openSecure;

@end


@protocol XMPPTransportDelegate

- (void)transport:(id <XMPPTransportProtocol>)transport didReceiveStanza:(NSXMLElement *)stanza;

@end
