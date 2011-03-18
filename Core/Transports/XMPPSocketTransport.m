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
#import "XMPPParser.h"
#import "NSXMLElementAdditions.h"

@implementation XMPPSocketTransport

@synthesize myJID;

- (id)initWithHost:(NSString *)givenHost port:(UInt16)givenPort
{
    if ((self = [super init]))
    {
        multicastDelegate = [[MulticastDelegate alloc] init];
        asyncSocket = [[AsyncSocket alloc] initWithDelegate:self];
        parser = [[XMPPParser alloc] initWithDelegate:self];
        host = givenHost;
        port = givenPort;
        state = XMPP_SOCKET_DISCONNECTED;
        numberOfBytesSent = 0;
        numberOfBytesReceived = 0;
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

- (BOOL)connect:(NSError **)errPtr
{
    state = XMPP_SOCKET_OPENING;
    return [asyncSocket connectToHost:host onPort:port error:errPtr];
}

- (BOOL)disconnect
{
    return YES;
}

- (void)restartStream
{
    
}

/**
 * Returns the version attribute from the servers's <stream:stream/> element.
 * This should be at least 1.0 to be RFC 3920 compliant.
 * If no version number was set, the server is not RFC compliant, and 0 is returned.
 **/
- (float)serverXmppStreamVersionNumber
{
	return [rootElement attributeFloatValueForName:@"version" withDefaultValue:0.0F];
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

/////////////////////////
#pragma mark PrivateAPI
/////////////////////////

/**
 * This method handles sending the opening <stream:stream ...> element which is needed in several situations.
 **/
- (void)sendOpeningNegotiation
{
	BOOL isRenegotiation = NO;
	
	if (state == XMPP_SOCKET_OPENING)
	{
		// TCP connection was just opened - We need to include the opening XML stanza
		NSString *s1 = @"<?xml version='1.0'?>";
		
		NSData *outgoingData = [s1 dataUsingEncoding:NSUTF8StringEncoding];
		
		DDLogSend(@"SEND: %@", s1);
		numberOfBytesSent += [outgoingData length];
		
		[asyncSocket writeData:outgoingData
				   withTimeout:TIMEOUT_WRITE
						   tag:TAG_WRITE_START];
	}

	if (state != XMPP_SOCKET_OPENING)
	{
		// We're restarting our negotiation.
		// This happens, for example, after securing the connection with SSL/TLS.
		isRenegotiation = YES;
		
		// Since we're restarting the XML stream, we need to reset the parser.
		[parser stop];
		[parser release];
		
		parser = [(XMPPParser *)[XMPPParser alloc] initWithDelegate:self];
	}
	else if (parser == nil)
	{
		// Need to create parser (it was destroyed when the socket was last disconnected)
		parser = [(XMPPParser *)[XMPPParser alloc] initWithDelegate:self];
	}
	
	NSString *xmlns = @"jabber:client";
	NSString *xmlns_stream = @"http://etherx.jabber.org/streams";
	
	NSString *temp, *s2;

    if (myJID)
    {
        temp = @"<stream:stream xmlns='%@' xmlns:stream='%@' version='1.0' to='%@'>";
        s2 = [NSString stringWithFormat:temp, xmlns, xmlns_stream, [myJID domain]];
    }
    else if ([host length] > 0)
    {
        temp = @"<stream:stream xmlns='%@' xmlns:stream='%@' version='1.0' to='%@'>";
        s2 = [NSString stringWithFormat:temp, xmlns, xmlns_stream, host];
    }
    else
    {
        temp = @"<stream:stream xmlns='%@' xmlns:stream='%@' version='1.0'>";
        s2 = [NSString stringWithFormat:temp, xmlns, xmlns_stream];
    }
    
	NSData *outgoingData = [s2 dataUsingEncoding:NSUTF8StringEncoding];
	
	DDLogSend(@"SEND: %@", s2);
	numberOfBytesSent += [outgoingData length];
	
	[asyncSocket writeData:outgoingData
			   withTimeout:TIMEOUT_WRITE
					   tag:TAG_WRITE_START];
	
	// Update status
	state = XMPP_SOCKET_NEGOTIATING;
	
	// For a reneogitation, we need to manually read from the socket.
	// This is because we had to reset our parser, which is usually used to continue the reading process.
	if (isRenegotiation)
	{
		[asyncSocket readDataWithTimeout:TIMEOUT_READ_START tag:TAG_READ_START];
	}
}

//////////////////////////////////
#pragma mark AsyncSocket Delegate
//////////////////////////////////
- (BOOL)onSocketWillConnect:(AsyncSocket *)socket
{
    [multicastDelegate transportWillConnect:self];
    return YES;
}

- (void)onSocket:(AsyncSocket *)socket didConnectToHost:(NSString *)givenHost port:(UInt16)givenPort
{
    [self sendOpeningNegotiation];
    [multicastDelegate transportDidStartNegotiation:self];
    // And start reading in the server's XML stream
	[asyncSocket readDataWithTimeout:TIMEOUT_READ_START tag:TAG_READ_START];
}

/**
 * Called when a socket has completed reading the requested data. Not called if there is an error.
 **/
- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	if (DEBUG_RECV_PRE)
	{
		NSString *dataAsStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		DDLogRecvPre(@"RECV: %@", dataAsStr);
		[dataAsStr release];
	}

	numberOfBytesReceived += [data length];
	[parser parseData:data];
}

//////////////////////////////////////
#pragma mark XMPPParser Delegate
//////////////////////////////////////

/**
 * Called when the xmpp parser has read in the entire root element.
 **/
- (void)xmppParser:(XMPPParser *)sender didReadRoot:(NSXMLElement *)root
{
	DDLogRecvPost(@"RECV: %@", [root compactXMLString]);

	// At this point we've sent our XML stream header, and we've received the response XML stream header.
	// We save the root element of our stream for future reference.
	// Digest Access authentication requires us to know the ID attribute from the <stream:stream/> element.

    [rootElement release];
    rootElement = [root retain];
    state = XMPP_SOCKET_CONNECTED;
    [multicastDelegate transportDidConnect:self];
}




@end
