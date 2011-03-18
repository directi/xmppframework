//
//  XMPPSocketTransport.m
//  iPhoneXMPP
//
//  Created by Chaitanya Gupta on 16/03/11.
//  Copyright 2011 Directi. All rights reserved.
//

#import "XMPPSocketTransport.h"
#import "MulticastDelegate.h"
#import "AsyncSocket.h"

@implementation XMPPSocketTransport

- (id)initWithHost:(NSString *)givenHost port:(UInt16)givenPort
{
    if ((self = [super init]))
    {
        multicastDelegate = [[MulticastDelegate alloc] init];
        asyncSocket = [[AsyncSocket alloc] init];
        host = givenHost;
        port = givenPort;
    }
    return self;
}

- (void)addDelegate:(id)delegate
{
    [multicastDelegate addDelegate:delegate];
}

- (void)removeDelegate:(id)delegate
{
    [multicastDelegate removeDelegate:delegate];
}

- (BOOL)connect:(NSError *)errPtr
{
    return YES;
}

- (BOOL)disconnect
{
    return YES;
}

- (BOOL)sendStanza:(NSXMLElement *)stanza
{
    return YES;
}

- (BOOL)sendStanzaWithString:(NSString *)string
{
    return YES;
}

- (BOOL)secure
{
    return YES;
}

@end
