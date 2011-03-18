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

@class AsyncSocket;
@class NSXMLElement;

@interface XMPPSocketTransport : NSObject <XMPPTransportProtocol> {
    MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
    AsyncSocket *asyncSocket;
    
    NSString *host;
    UInt16 port;
}

- (id)initWithHost:(NSString *)host port:(UInt16)port;

- (void)addDelegate:(id)delegate;
- (void)removeDelegate:(id)delegate;
- (BOOL)connect:(NSError *)errPtr;
- (BOOL)disconnect;
- (BOOL)sendStanza:(NSXMLElement *)stanza;
- (BOOL)sendStanzaWithString:(NSString *)string;
- (BOOL)secure;

@end
