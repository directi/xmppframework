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

#pragma -
#pragma RequestResponsePair Class
@implementation RequestResponsePair

@synthesize request=request_;
@synthesize response=response_;

- (id) initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response
{
	if( (self = [super init]) ) {
		request_ = request;
		response_ = response;
	}
	return self;
}

- (void)dealloc
{
	[request_ release];
	[response_ release];
	[super dealloc];
}
@end

#pragma -
#pragma BoshWindowManager Class

@implementation BoshWindowManager

@synthesize windowSize;
@synthesize outstandingRequests;

- (long long)getRidInBody:(NSXMLElement *)body
{
    return [[[body attributeForName:@"rid"] stringValue] longLongValue];
}

- (NSString *)stringFromInt:(long long)num
{
	return [NSString stringWithFormat:@"%qi",num];
}

- (id)initWithDelegate:(id)del rid:(long long)rid
{
	if((self = [super init]))
	{
		window = [[NSMutableDictionary alloc] initWithCapacity:4];
		windowSize = 0;
		outstandingRequests = 0;
		maxRidSent = rid;
		maxRidReceived = rid;
		delegate = del;
	}
	return self;
}

- (void)sentRequest:(NSXMLElement *)request
{
	NSAssert( [self canSendMoreRequests], @"Sending request when should not be: Exceeding request count" );
	long long requestRid = [self getRidInBody:request];
	NSAssert ( requestRid == maxRidSent + 1, @"Sending request with rid = %qi greater than expected rid = %qi", requestRid, maxRidSent + 1);
	++maxRidSent;
	[window setValue:[[RequestResponsePair alloc] initWithRequest:request response:nil]  forKey:[self stringFromInt:requestRid]];
}

- (void)processResponses
{
	while (true)
	{
		RequestResponsePair *requestResponsePair = [window valueForKey:[self stringFromInt:(maxRidReceived+1)]];
		if( requestResponsePair.response == nil ) break;
		[[requestResponsePair.response retain] autorelease];
		[window removeObjectForKey:[ self stringFromInt:(maxRidReceived + 1) ]];
		++maxRidReceived;
		[delegate broadcastStanzas:requestResponsePair.response];
	}
}

- (void)recievedResponse:(NSXMLElement *)response forRid:(long long)rid
{
	NSAssert(rid > maxRidReceived, @"Recieving response for rid = %qi where maxRidReceived = %qi", rid, maxRidReceived);
	NSAssert(rid < maxRidReceived + windowSize, @"Recieved response for a request outside the rid window. responseRid = %qi, maxRidReceived = %qi, windowSize = %qi", rid, maxRidReceived, windowSize);
	RequestResponsePair *requestResponsePair = [window valueForKey:[self stringFromInt:rid]];
	NSAssert( requestResponsePair != nil, @"Response rid not in queue");
	requestResponsePair.response = response;
	[self processResponses];
}

- (BOOL)canSendMoreRequests
{
	return (maxRidSent - maxRidReceived) < windowSize;
}

- (BOOL)canLetServerHoldRequests:(long long)hold
{
	return (maxRidSent - maxRidReceived) < hold;
}
- (NSXMLElement *)getRequestForRid:(long long)rid
{
	NSAssert( rid - maxRidReceived > 0 && [window count] > (rid - maxRidReceived), @"Error Access request for rid = %qi, where maxRidReceived = %qi and [requestQueue count] = %qi", rid, maxRidReceived, [window count]);
	return [window valueForKey:[self stringFromInt:rid]];
}

- (void) dealloc
{
    [window release];
    [super dealloc];
}
@end

@interface BoshTransport()
- (void)setInactivity:(NSString *)givenInactivity;
- (void)setSecure:(NSString *)isSecure;
- (void)setRequests:(NSString *)maxRequests;
@end

#pragma -
#pragma BoshTranshport Class
@implementation BoshTransport

@synthesize wait = wait_;
@synthesize hold = hold_;
@synthesize lang = lang_;
@synthesize domain = domain_;
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

- (id)initWithUrl:(NSString *)url forDomain:(NSString *)domain
{
    return [self initWithUrl:url forDomain:(NSString *)domain withDelegate:nil];
}

- (id)initWithUrl:(NSString *)url forDomain:(NSString *)domain withDelegate:(id<XMPPTransportDelegate>)delegate
{
    self = [super init];
    if(self)
    {		
        boshVersion = @"1.6";
        lang_ = @"en";
        content = [NSString stringWithFormat:@"text/xml; charset=utf-8"];
        wait_ = [[NSNumber alloc] initWithDouble:60.0];
        hold_ = [[NSNumber alloc] initWithInt:1];
        ack = [NSNumber numberWithInt:1];

        nextRidToSend = [self generateRid];
        
        multicastDelegate = [[MulticastDelegate alloc] init];
        if( delegate != nil ) [multicastDelegate addDelegate:delegate];

        STREAM_NS = @"http://etherx.jabber.org/streams";
        BODY_NS = @"http://jabber.org/protocol/httpbind";
        XMPP_NS = @"urn:xmpp:xbosh";
		
        sid_ = nil;
        inactivity = [[NSNumber alloc] initWithInt:0];
        requests = [[NSNumber alloc] initWithInt:2];
        url_ = [url copy];
        domain_ = [domain copy];
        myJID_ = nil;
		state = DISCONNECTED;
        
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
    NSLog(@"BOSH: Connecting to %@ with jid = %@", self.domain, [self.myJID bare]);
    
    if(![self canConnect]) return NO;
    state = CONNECTING;
    [multicastDelegate transportWillConnect:self];
    return [self createSession:error];
}

- (void)restartStream
{
    if(![self isConnected])
    {
        NSLog(@"BOSH: Need to be connected to restart the stream.");
        return ;
    }
    NSLog(@"Bosh: Will Restart Stream");
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: self.lang, @"xml:lang", @"true", @"xmpp:restart", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys:XMPP_NS, @"xmpp", nil];
    
    [self sendRequest:nil attributes:attr namespaces:ns responseHandler:nil errorHandler:nil];
}

- (void)disconnect
{
    if(![self isConnected])
    {
        NSLog(@"BOSH: Need to be connected to disconnect");
        return;
    }
    NSLog(@"Bosh: Will Terminate Session");
    [multicastDelegate transportWillDisconnect:self];
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: self.lang, @"xml:lang", @"terminate", @"type", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: BODY_NS, @"", nil];
    state = DISCONNECTING;
    [self sendRequest:nil attributes:attr namespaces:ns responseHandler:@selector(disconnectSessionResponseHandler:) errorHandler:nil];
}

- (BOOL)sendStanza:(NSXMLElement *)stanza
{
    if (![self isConnected])
    {
        NSLog(@"BOSH: Need to be connected to be able to send stanza");
        return NO;
    }
    [pendingXMPPStanzas addObject:stanza];
    [self trySendingStanzas];
    return YES;
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

- (BOOL)isConnected
{
    return state == CONNECTED;
}

- (BOOL)canConnect
{
    if( state != DISCONNECTED )
    {
        NSLog(@"@BOSH: Either disconnecting or still connected to the server. Disconnect First.");
        return NO;
    }
    if(!self.domain)
    {
        NSLog(@"BOSH: Called Connect with specifying the domain");
        return NO;
    }
    if(!self.myJID)
    {
        NSLog(@"BOSH: Called connect without setting the jid");
        return NO;
    }
    return YES;
}

- (BOOL) createSession:(NSError **)error
{
    NSArray *keys = [NSArray arrayWithObjects:@"content", @"hold", @"to", @"ver", @"wait", @"ack", @"xml:lang", @"from", @"secure", nil];
    NSArray *objects = [NSArray arrayWithObjects:content, self.hold, self.domain, boshVersion, self.wait, ack, self.lang, [self.myJID bare], @"false", nil];
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjects:[self convertToStrings:objects] forKeys:keys];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: XMPP_NS, @"xmpp", nil];
    
    NSXMLElement *requestPayload = [self newBodyElementWithPayload:nil attributes:attr namespaces:ns];
    [self sendHTTPRequestWithBody:requestPayload responseHandler:@selector(createSessionResponseHandler:) errorHandler:nil];
    [requestPayload release];
    return YES;
}

- (void)createSessionResponseHandler:(ASIHTTPRequest *)request
{
    NSLog(@"BOSH: Response = %@", [request responseString]);
    state = CONNECTED;
    NSXMLElement *rootElement = [self parseXMLData:[request responseData]];
	
    NSArray *responseAttributes = [rootElement attributes];
    /* Setting inactivity, sid, wait, hold, ack, lang, authid, secure, requests */
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
    
	boshWindowManager = [[BoshWindowManager alloc] initWithDelegate:self rid:[self getRidInRequest:rootElement]];
	[boshWindowManager setWindowSize:[requests unsignedIntValue]];
	
    [multicastDelegate transportDidConnect:self];
    [multicastDelegate transportDidStartNegotiation:self];
    
    if( [(NSXMLNode *)rootElement childCount] > 0 )
        [self broadcastStanzas:rootElement];
    
    /* should we send these requests after a delay?? */
    [self sendRequestsToHold];
}

- (void)disconnectSessionResponseHandler:(ASIHTTPRequest *)request
{
    state = DISCONNECTED;
    [boshWindowManager release];
    [multicastDelegate removeAllDelegates];
    [pendingXMPPStanzas removeAllObjects];
    self.myJID = nil;
    nextRidToSend = [self generateRid];
    ack = [NSNumber numberWithInt:1];
    self.hold = [NSNumber numberWithInt:1];
    self.wait = [NSNumber numberWithDouble:60.0];
    [inactivity release];
    inactivity = [NSNumber numberWithInt:0];
    self.sid = nil;
    self.authid = nil;
    [multicastDelegate transportDidDisconnect:self];
}

- (void)sendRequest:(NSArray *)bodyPayload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces responseHandler:(SEL)responseHandler errorHandler:(SEL)errorHandler
{
	NSXMLElement *requestPayload = [self newBodyElementWithPayload:bodyPayload attributes:attributes namespaces:namespaces];
	[boshWindowManager sentRequest:requestPayload];
    [self sendHTTPRequestWithBody:requestPayload responseHandler:responseHandler errorHandler:errorHandler];
	[requestPayload release];
}

- (void)trySendingStanzas
{
    if( [boshWindowManager canSendMoreRequests] && [pendingXMPPStanzas count] > 0)
	{
		[self sendRequest:pendingXMPPStanzas attributes:nil namespaces:nil responseHandler:nil errorHandler:nil];
		[pendingXMPPStanzas removeAllObjects];
	}
}

- (void)sendRequestsToHold
{
    while( [boshWindowManager canLetServerHoldRequests:[self.hold unsignedIntValue]] ) 
		[self sendRequest:nil attributes:nil namespaces:nil responseHandler:nil errorHandler:nil];
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

#pragma mark -
#pragma mark HTTP Request Response

/* Should call processRequestQueue after some timeOut */
- (void)requestFinished:(ASIHTTPRequest *)request
{
    NSString *responseString = [request responseString];
    NSLog(@"BOSH: response string = %@", responseString);
    NSString *postBodyString = [[NSString alloc] initWithData:[request postBody] encoding:NSUTF8StringEncoding];
    NSXMLElement *postBody = [[NSXMLElement alloc] initWithXMLString:postBodyString error:nil];
	[boshWindowManager recievedResponse:[self parseXMLData:[request responseData]] forRid:[self getRidInRequest:postBody]];
    [self sendRequestsToHold];
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSLog(@"BOSH: request Failed = %@", [request error]);
    [request startSynchronous];
}

- (void)sendHTTPRequestWithBody:(NSXMLElement *)body responseHandler:(SEL)responseHandler errorHandler:(SEL)errorHandler
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
#pragma mark utilities

- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces
{
    attributes = attributes?attributes:[NSMutableDictionary dictionaryWithCapacity:3];
    namespaces = namespaces?namespaces:[NSMutableDictionary dictionaryWithCapacity:1];
	
    /* Adding sid attribute on every outgoing request */
    if( self.sid ) [attributes setValue:self.sid forKey:@"sid"];
	
    [attributes setValue:[NSString stringWithFormat:@"%d", nextRidToSend] forKey:@"rid"];
	
    /* Adding the BODY_NS namespace on every outgoing request */
    [namespaces setValue:BODY_NS forKey:@""];
	
    NSXMLElement *body = [[NSXMLElement alloc] initWithName:@"body"];
	
    [body setNamespaces:[self createXMLNodeArrayFromDictionary:namespaces ofType:NAMESPACE_TYPE]];
    [body setAttributes:[self createXMLNodeArrayFromDictionary:attributes ofType:ATTR_TYPE]];
	
    if(payload != nil)
        for(NSXMLElement *child in payload)
            [body addChild:child];

	++nextRidToSend;
	
    return body;
}

- (long long)getRidInRequest:(NSXMLElement *)body
{
    return [[[body attributeForName:@"rid"] stringValue] longLongValue];
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

- (NSArray *)createXMLNodeArrayFromDictionary:(NSDictionary *)dict ofType:(XMLNodeType)type
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (NSString *key in dict) {
        NSString *value = [dict objectForKey:key];
        NSXMLNode *node;
        
        if(type == ATTR_TYPE) 
            node = [NSXMLNode attributeWithName:key stringValue:value];
        else if(type == NAMESPACE_TYPE)
            node = [NSXMLNode namespaceWithName:key stringValue:value];
        else 
            NSLog(@"BOSH: Wrong Type Passed to createArrayFrom Dictionary");
		
        [array addObject:node];
    }
    return [array autorelease];
}

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

- (void)dealloc
{
    [wait_ release];
    [hold_ release];
    [multicastDelegate release];
    [inactivity release];
    [requests release];
    [url_ release];
    [domain_ release];
    [myJID_ release];
    [authid release];
    [sid_ release];
    [super dealloc];
}
@end
