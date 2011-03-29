//
//  BoshTransport.m
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "BoshTransport.h"
#import "DDXML.h"
#import "NSXMLElementAdditions.h"

#pragma mark -
#pragma mark Private Accessor Methods
@interface BoshTransport()
- (void)setInactivity:(NSString *)givenInactivity;
- (void)setSecure:(NSString *)isSecure;
- (void)setRequests:(NSString *)maxRequests;
@end

#pragma mark Private utilities
@interface BoshTransport()
- (long long) generateRid;	
- (NSArray *) convertToStrings:(NSArray *)array;
- (SEL)setterForProperty:(NSString *)property;
- (NSNumber *)numberFromString:(NSString *)stringNumber;
@end

#pragma mark http
@interface BoshTransport()
- (void) sendRequestWithBody:(NSXMLElement *)body responseHandler:(SEL)responseHandler errorHandler:(SEL)errorHandler;
- (void)broadcastStanzas:(NSXMLNode *)node;
- (void)startSessionWithRequest:(NSXMLElement *)body;
- (void)trySendingStanzas;
- (void)sendRequest:(NSArray *)bodyPayload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
@end

#pragma mark xml
@interface BoshTransport()
- (long long)getRidInRequest:(NSXMLElement *)body;
- (NSXMLElement *) newRequestWithPayload:(NSArray *)payload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
- (NSArray *) createAttributeArrayFromDictionary:(NSDictionary *)attributes;
- (NSArray *) createNamespaceArrayFromDictionary:(NSDictionary *)namespacesDictionary;
- (NSXMLElement *) parseXMLData:(NSData *)xml;
- (NSXMLElement *) parseXMLString:(NSString *)xml;
@end


@implementation BoshTransport

@synthesize wait = wait_;
@synthesize hold = hold_;
@synthesize lang = lang_;
@synthesize host = host_;
@synthesize myJID = myJID_;
@synthesize sid = sid_;
@synthesize url = url_;
@synthesize inactivity;
@synthesize secure;
@synthesize authid;
@synthesize requests;

#pragma mark -
#pragma mark Private Accessor Method Implementation

- (void)setInactivity:(NSString *)inactivityString
{
    NSNumber *givenInactivity = [self numberFromString:inactivityString];
    [inactivity autorelease];
    inactivity = [givenInactivity retain];
}

- (void)setRequests:(NSString *)requestsString
{
    NSNumber *maxRequests = [self numberFromString:requestsString];
    [requests autorelease];
    requests = [maxRequests retain];
}

- (void)setSecure:(NSString *)isSecure
{
    if ([isSecure isEqualToString:@"true"]) secure=YES;
    else secure = NO;
}

#pragma mark -
#pragma mark init

- (id)initWithUrl:(NSString *)url forHost:(NSString *)host
{
    return [self initWithUrl:url forHost:host withDelegate:nil];
}

- (id)initWithUrl:(NSString *)url forHost:(NSString *)host withDelegate:(id<XMPPTransportDelegate>)delegate
{
    self = [super init];
    if(self)
    {		
        boshVersion = @"1.6";
        lang_ = @"en";
        content = [NSString stringWithFormat:@"text/xml; charset=utf-8"];
        wait_ = [[NSNumber alloc] initWithDouble:60.0];
        hold_ = [[NSNumber alloc] initWithInt:1];
        ack = [[NSNumber alloc] initWithInt:1];

        nextRidToSend = [self generateRid];
        
        multicastDelegate = [[MulticastDelegate alloc] init];
        if( delegate != nil ) [multicastDelegate addDelegate:delegate];

        STREAM_NS = @"http://etherx.jabber.org/streams";
        BODY_NS = @"http://jabber.org/protocol/httpbind";
        XMPP_NS = @"urn:xmpp:xbosh";
		
        sid_ = nil;
        inactivity = [[NSNumber alloc] initWithInt:0];
        requests = [[NSNumber alloc] initWithInt:0];
        url_ = url;
        host_ = host;
        myJID_ = nil;
		
		/* Keeping a random capacity right now */
		pendingXMPPStanzas = [[NSMutableArray alloc] initWithCapacity:25];
    }
    return self;
}

#pragma mark -
#pragma mark Transport Protocols
/* Implemet this as well */
- (float)serverXmppStreamVersionNumber
{
    return 1.0;
}

- (BOOL)connect:(NSError **)error
{
    NSLog(@"BOSH: Connecting to %@ with jid = %@", self.host, [self.myJID bare]);
	
    if(!self.host)
    {
        NSLog(@"BOSH: Called Connect with specifying the host");
        return NO;
    }
	
    if(!self.myJID)
    {
        NSLog(@"BOSH: Called connect without setting the jid");
        return NO;
    }
    
    [multicastDelegate transportWillConnect:self];
    
    NSArray *keys = [NSArray arrayWithObjects:@"content", @"hold", @"to", @"ver", @"wait", @"ack", @"xml:lang", @"from", @"secure", nil];
    NSArray *objects = [NSArray arrayWithObjects:content, self.hold, self.host, boshVersion, self.wait, ack, self.lang, [self.myJID bare], @"false", nil];
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjects:[self convertToStrings:objects] forKeys:keys];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: XMPP_NS, @"xmpp", nil];
    
    NSXMLElement *requestPayload = [self newRequestWithPayload:nil attributes:attr namespaces:ns];
    [self sendRequestWithBody:requestPayload responseHandler:@selector(sessionResponseHandler:) errorHandler:nil];
    [requestPayload release];
    return YES;
}

- (void)restartStream
{
    NSLog(@"Bosh: Will Restart Stream");
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: self.lang, @"xml:lang", @"true", @"xmpp:restart", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: BODY_NS, @"", XMPP_NS, @"xmpp", nil];
    [self sendRequest:nil attributes:attr namespaces:ns];
}

- (void)disconnect
{
    NSLog(@"Bosh: Will Terminate Session");
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: self.lang, @"xml:lang", @"terminate", @"type", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: BODY_NS, @"", nil];
    [self sendRequest:nil attributes:attr namespaces:ns];
}

- (BOOL)sendStanza:(NSXMLElement *)stanza
{
    [pendingXMPPStanzas addObject:stanza];
    [self trySendingStanzas];
    return TRUE;
}

- (BOOL)sendStanzaWithString:(NSString *)string
{
    NSXMLElement *payload = [self parseXMLString:string];
    return [self sendStanza:payload];
}

- (void)addDelegate:(id)delegate
{
    [multicastDelegate addDelegate:delegate];
}

- (void) removeDelegate:(id)delegate
{
    [multicastDelegate removeDelegate:delegate];
}

#pragma mark -
#pragma mark BOSH

- (void)sendRequest:(NSArray *)bodyPayload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces
{
	NSXMLElement *requestPayload = [self newRequestWithPayload:bodyPayload attributes:attributes namespaces:namespaces];
	[self sendRequestWithBody:requestPayload responseHandler:nil errorHandler:nil];
	[boshWindowManager sentRequest:requestPayload];
	[requestPayload release];
}

- (void)trySendingStanzas
{
    if( [boshWindowManager canSendMoreRequests] && [pendingXMPPStanzas count] > 0)
	{
		[self sendRequest:pendingXMPPStanzas attributes:nil namespaces:nil];
		[pendingXMPPStanzas removeAllObjects];
	}
}

- (void)sendRequestsToHold
{
    while( [boshWindowManager canLetServerHoldRequests:[self.hold unsignedIntValue]] ) 
		[self sendRequest:nil attributes:nil namespaces:nil];
}

/*
  For each received stanza the client might send out packets.
  We should ideally put all the request in the queue and call
  processRequestQueue with a timeOut.
*/ 
- (void)broadcastStanzas:(NSXMLNode *)node
{
    while( (node = [node nextNode]) )
    {
        if([node level] == 1)
        {
            NSLog(@"BOSH: Passing to delegates the stanza = %@", node);
            [multicastDelegate transport:self didReceiveStanza:[(NSXMLElement *)node copy]];
        }
    }
}

- (void)sessionResponseHandler:(ASIHTTPRequest *)request
{
    [multicastDelegate transportDidConnect:self];
    NSLog(@"BOSH: Response = %@", [request responseString]);
    NSXMLElement *rootElement = [self parseXMLData:[request responseData]];
	
    NSArray *responseAttributes = [rootElement attributes];
    for(NSXMLNode *attr in responseAttributes)
    {
        NSString *attrName = [attr name];
        NSString *attrValue = [attr stringValue];
        SEL setter = [self setterForProperty:attrName];
        
        if([self respondsToSelector:setter]) 
            [self performSelector:setter withObject:attrValue];
    }

    /* Not doing anything with namespaces right now - because chirkut doesn't send it */
    //NSArray *responseNamespaces = [rootElement namespaces];
    
    [multicastDelegate transportDidStartNegotiation:self];
	boshWindowManager = [[BoshWindowManager alloc] initWithDelegate:self rid:[self getRidInRequest:rootElement]];
	[boshWindowManager setWindowSize:[requests unsignedIntValue]];
	
    if( [(NSXMLNode *)rootElement childCount] > 0 )
        [self broadcastStanzas:rootElement];

    /* should we send these requests after a delay?? */
    [self sendRequestsToHold];
}

- (void)startSessionWithRequest:(NSXMLElement *)body
{
    
}

#pragma mark -
#pragma mark HTTP

/* Should call processRequestQueue after some timeOut */
- (void)requestFinished:(ASIHTTPRequest *)request
{
    NSString *responseString = [request responseString];
    NSLog(@"BOSH: response string = %@", responseString);
	[boshWindowManager recievedResponse:[self parseXMLData:[request responseData]]];
    [self sendRequestsToHold];
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSLog(@"BOSH: request Failed = %@", [request error]);
}

- (void)sendRequestWithBody:(NSXMLElement *)body responseHandler:(SEL)responseHandler errorHandler:(SEL)errorHandler
{
    NSURL *url = [NSURL URLWithString:self.url];
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    [request setRequestMethod:@"POST"];
    [request setDelegate:self];
    [request setTimeOutSeconds:[self.wait doubleValue]+4];
    
    if(body) [request appendPostData:[[body compactXMLString] dataUsingEncoding:NSUTF8StringEncoding]];
    if(responseHandler) [request setDidFinishSelector:responseHandler];
    if(errorHandler) [request setDidFailSelector:errorHandler];
    
    [request startAsynchronous];
    
    NSLog(@"BOSH: Async Request Sent with data = %@", body);
    return;
}

#pragma mark -
#pragma mark XML

- (long long)getRidInRequest:(NSXMLElement *)body
{
    return [[[body attributeForName:@"rid"] stringValue] longLongValue];
}

- (NSXMLElement *)newRequestWithPayload:(NSArray *)payload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces
{
    attributes = attributes?attributes:[NSMutableDictionary dictionaryWithCapacity:3];
    namespaces = namespaces?namespaces:[NSMutableDictionary dictionaryWithCapacity:1];
	
    /* Adding sid attribute on every outgoing request */
    if( self.sid ) [attributes setValue:self.sid forKey:@"sid"];
	
    [attributes setValue:[NSString stringWithFormat:@"%d", nextRidToSend] forKey:@"rid"];
	
    /* Adding the BODY_NS namespace on every outgoing request */
    [namespaces setValue:BODY_NS forKey:@""];
	
    NSXMLElement *boshRequest = [[NSXMLElement alloc] initWithName:@"body"];
	
    [boshRequest setNamespaces:[self createNamespaceArrayFromDictionary:namespaces]];
    [boshRequest setAttributes:[self createAttributeArrayFromDictionary:attributes]];
	
    if(payload != nil)
        for(NSXMLElement *child in payload)
            [boshRequest addChild:child];

	++nextRidToSend;
	
    return boshRequest;
}

- (NSXMLElement *)returnRootElement:(NSXMLDocument *)doc
{
    NSXMLElement *rootElement = [doc rootElement];
    [doc release];
    return rootElement;	
}

- (NSXMLElement *)parseXMLString:(NSString *)xml
{
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:nil];
    return [self returnRootElement:doc];
}

- (NSXMLElement *)parseXMLData:(NSData *)xml
{
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:xml options:0 error:nil];
    return [self returnRootElement:doc];
}

- (NSArray *)createArrayFromDictionary:(NSDictionary *)dictionary ofType:(NSString *)type
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (NSString *key in dictionary) {
        NSString *value = [dictionary objectForKey:key];
        NSXMLNode *node;
        
        if([type isEqualToString:@"attributes"]) 
            node = [NSXMLNode attributeWithName:key stringValue:value];
        else if([type isEqualToString:@"namespaces"])
            node = [NSXMLNode namespaceWithName:key stringValue:value];
        else 
            NSLog(@"BOSH: Wrong Type Passed to createArrayFrom Dictionary");
		
        [array addObject:node];
    }
    return [array autorelease];
}

- (NSArray *)createAttributeArrayFromDictionary:(NSDictionary *)attributesDictionary
{
    return [self createArrayFromDictionary:attributesDictionary ofType:@"attributes"];
}

- (NSArray *)createNamespaceArrayFromDictionary:(NSDictionary *)namespacesDictionary
{
    return [self createArrayFromDictionary:namespacesDictionary ofType:@"namespaces"];
}

#pragma mark -
#pragma mark utilities

- (long long)generateRid
{
    return (arc4random() % 1000000000LL + 1000000001LL);
}

- (NSArray *)convertToStrings:(NSArray *)array
{
    NSMutableArray *mutableArray = [[NSMutableArray alloc] initWithCapacity:0];
    for(id element in array)
        [mutableArray addObject:[NSString stringWithFormat:@"%@", element]];
    return [mutableArray autorelease];
}

- (SEL)setterForProperty:(NSString *)property
{
    NSString *setter = @"set";
    setter = [setter stringByAppendingString:[property capitalizedString]];
    setter = [setter stringByAppendingString:@":"];
    return NSSelectorFromString(setter);
}

- (NSNumber *)numberFromString:(NSString *)stringNumber
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    NSNumber *number = [formatter numberFromString:stringNumber];
    [formatter release];
    return number;
}
@end
