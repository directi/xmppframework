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

@interface NSMutableSet(BoshTransport)
- (void)addLongLong:(long long)number;
- (void)removeLongLong:(long long)number;
- (BOOL)containsLongLong:(long long)number;
@end

@interface NSMutableDictionary(BoshTransport) 
- (void)setObject:(id)anObject forLongLongKey:(long long)number;
- (void)removeObjectForLongLongKey:(long long)number;
- (id)objectForLongLongKey:(long long)number;
@end

@implementation NSMutableSet(BoshTransport)
- (void)addLongLong:(long long)number 
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    [self addObject:nsNumber];
}
- (void)removeLongLong:(long long)number
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    [self removeObject:nsNumber];
}
- (BOOL)containsLongLong:(long long)number
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    return [self containsObject:nsNumber];
}
@end

@implementation NSMutableDictionary(BoshTransport)
- (void)setObject:(id)anObject forLongLongKey:(long long)number 
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    [self setObject:anObject forKey:nsNumber];
}

- (void)removeObjectForLongLongKey:(long long)number 
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    [self removeObjectForKey:nsNumber];
}
- (id)objectForLongLongKey:(long long)number
{
    NSNumber *nsNumber = [NSNumber numberWithLongLong:number];
    return [self objectForKey:nsNumber];
}
@end

#pragma -
#pragma RequestResponsePair Class
@implementation RequestResponsePair

@synthesize request=request_;
@synthesize response=response_;

- (id) initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response
{
	if( (self = [super init]) ) 
    {
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
@synthesize maxRidReceived;

- (id)initWithRid:(long long)rid
{
	if((self = [super init]))
	{
		windowSize = 0;
		maxRidSent = rid;
		maxRidReceived = rid;
        receivedRids = [[NSMutableSet alloc] initWithCapacity:2];
	}
	return self;
}

- (void)sentRequestForRid:(long long)rid
{
	NSAssert(![self isWindowFull], @"Sending request when should not be: Exceeding request count" );
	NSAssert2(rid == maxRidSent + 1, @"Sending request with rid = %qi greater than expected rid = %qi", rid, maxRidSent + 1);
	++maxRidSent;
}

- (void)recievedResponseForRid:(long long)rid
{
	NSAssert2(rid > maxRidReceived, @"Recieving response for rid = %qi where maxRidReceived = %qi", rid, maxRidReceived);
	NSAssert3(rid <= maxRidReceived + windowSize, @"Recieved response for a request outside the rid window. responseRid = %qi, maxRidReceived = %qi, windowSize = %qi", rid, maxRidReceived, windowSize);
    [receivedRids addLongLong:rid];
	while ( [receivedRids containsLongLong:(maxRidReceived + 1)] )
	{
		++maxRidReceived;
	}
}

- (BOOL)isWindowFull
{
	return (maxRidSent - maxRidReceived) == windowSize;
}

- (BOOL)isWindowEmpty
{
	return (maxRidSent - maxRidReceived) < 1;
}

- (void) dealloc
{
    [receivedRids release];
    [super dealloc];
}
@end

static const int RETRY_COUNT_LIMIT = 25;
static const NSTimeInterval RETRY_DELAY = 1.0;

static const NSString *CONTENT_TYPE = @"text/xml; charset=utf-8";
static const NSString *BODY_NS = @"http://jabber.org/protocol/httpbind";
static const NSString *XMPP_NS = @"urn:xmpp:xbosh";

@interface BoshTransport()
@property(readwrite, assign) NSError *disconnectError;
- (void)setInactivity:(NSString *)givenInactivity;
- (void)setSecure:(NSString *)isSecure;
- (void)setRequests:(NSString *)maxRequests;
- (BOOL)canConnect;
- (void)handleAttributesInResponse:(NSXMLElement *)parsedResponse;
- (NSString *)logRequestResponse:(NSData *)data;
- (void)createSessionResponseHandler:(NSXMLElement *)parsedResponse;
- (void)handleDisconnection;
- (long long)generateRid;
- (SEL)setterForProperty:(NSString *)property;
- (NSNumber *)numberFromString:(NSString *)stringNumber;
- (void)sendHTTPRequestWithBody:(NSXMLElement *)body;
- (void)broadcastStanzas:(NSXMLNode *)node;
- (void)trySendingStanzas;
- (void)makeBodyAndSendHTTPRequestWithPayload:(NSArray *)bodyPayload 
                                   attributes:(NSMutableDictionary *)attributes 
                                   namespaces:(NSMutableDictionary *)namespaces;
- (long long)getRidInRequest:(NSXMLElement *)body;
- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload 
                                 attributes:(NSMutableDictionary *)attributes 
                                 namespaces:(NSMutableDictionary *)namespaces;
- (NSArray *)newXMLNodeArrayFromDictionary:(NSDictionary *)dict 
                                    ofType:(XMLNodeType)type;
- (NSXMLElement *)parseXMLData:(NSData *)xml;
- (NSXMLElement *)parseXMLString:(NSString *)xml;
- (BOOL) createSession:(NSError **)error;
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
@synthesize disconnectError = disconnectError_;

#pragma mark -
#pragma mark Private Accessor Method Implementation

- (void)setInactivity:(NSString *)inactivityString
{
    NSNumber *givenInactivity = [self numberFromString:inactivityString];
    inactivity = [givenInactivity unsignedIntValue];
}

- (void)setRequests:(NSString *)requestsString
{
    NSNumber *maxRequests = [self numberFromString:requestsString];
    [boshWindowManager setWindowSize:[maxRequests unsignedIntValue]];
    requests = [maxRequests unsignedIntValue];
}

- (void)setSecure:(NSString *)isSecure
{
    if ([isSecure isEqualToString:@"true"]) secure=YES;
    else secure = NO;
}

#pragma mark -
#pragma mark init

- (id)initWithUrl:(NSURL *)url forDomain:(NSString *)domain
{
    return [self initWithUrl:url forDomain:(NSString *)domain withDelegate:nil];
}

- (id)initWithUrl:(NSURL *)url 
        forDomain:(NSString *)domain
     withDelegate:(id<XMPPTransportDelegate>)delegate
{
    self = [super init];
    if(self)
    {		
        boshVersion = @"1.6";
        lang_ = @"en";
        wait_ = 60.0;
        hold_ = 1;

        nextRidToSend = [self generateRid];
        maxRidProcessed = nextRidToSend - 1;
        
        multicastDelegate = [[MulticastDelegate alloc] init];
        if( delegate != nil ) [multicastDelegate addDelegate:delegate];
		
        sid_ = nil;
        inactivity = 0.0;
        requests = 2;
        url_ = [url retain];

        domain_ = [domain copy];
        myJID_ = nil;
        state = DISCONNECTED;
        disconnectError_ = nil;

        /* Keeping a random capacity right now */
        pendingXMPPStanzas = [[NSMutableArray alloc] initWithCapacity:25];
        requestResponsePairs = [[NSMutableDictionary alloc] initWithCapacity:3];
        retryCounter = 0;
        
        boshWindowManager = [[BoshWindowManager alloc] initWithRid:(nextRidToSend - 1)];
        [boshWindowManager setWindowSize:1];
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
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"true", @"xmpp:restart", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys:XMPP_NS, @"xmpp", nil];
    [self makeBodyAndSendHTTPRequestWithPayload:nil attributes:attr namespaces:ns];
}

- (void)disconnect
{
    if(![self isConnected])
    {
        NSLog(@"BOSH: Need to be connected to disconnect");
        return;
    }
    NSLog(@"Bosh: Will Terminate Session");
    state = DISCONNECTING;
    [multicastDelegate transportWillDisconnect:self];
    [self trySendingStanzas];
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

- (BOOL)createSession:(NSError **)error
{
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithCapacity:8];
   
    [attr setObject:CONTENT_TYPE forKey:@"content"];
    [attr setObject:[NSString stringWithFormat:@"%u", self.hold] forKey:@"hold"];
    [attr setObject:self.domain forKey:@"to"];
    [attr setObject:boshVersion forKey:@"ver"];
    [attr setObject:[NSString stringWithFormat:@"%u", self.wait] forKey:@"wait"];
    [attr setObject:[self.myJID bare] forKey:@"from"];
    [attr setObject:@"false" forKey:@"secure"];
    [attr setObject:[NSString stringWithFormat:@"%u", self.inactivity] forKey:@"inactivity"];
    
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys: XMPP_NS, @"xmpp", nil];
    
    [self makeBodyAndSendHTTPRequestWithPayload:nil attributes:attr namespaces:ns];
    
    return YES;
}

- (void)makeBodyAndSendHTTPRequestWithPayload:(NSArray *)bodyPayload 
                                   attributes:(NSMutableDictionary *)attributes 
                                   namespaces:(NSMutableDictionary *)namespaces
{
	NSXMLElement *requestPayload = [self newBodyElementWithPayload:bodyPayload 
                                                        attributes:attributes 
                                                        namespaces:namespaces];
    [self sendHTTPRequestWithBody:requestPayload];
    [boshWindowManager sentRequestForRid:nextRidToSend];
    ++nextRidToSend;
    
    [requestPayload release];
}

- (void)sendTerminateRequest
{
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"terminate", @"type", nil];
    [self makeBodyAndSendHTTPRequestWithPayload:nil attributes:attr namespaces:nil];
}

- (void)trySendingStanzas
{
    if( state != DISCONNECTED && ![boshWindowManager isWindowFull] ) 
    {
        if (state == CONNECTED) {
            if ( [pendingXMPPStanzas count] > 0 )
            {
                [self makeBodyAndSendHTTPRequestWithPayload:pendingXMPPStanzas 
                                                 attributes:nil namespaces:nil];
                [pendingXMPPStanzas removeAllObjects];
            } else if ( [boshWindowManager isWindowEmpty] ) {
                [self makeBodyAndSendHTTPRequestWithPayload:nil 
                                                 attributes:nil namespaces:nil];                
            }
        }
        else if(state == DISCONNECTING) 
        { 
            [self sendTerminateRequest]; 
        }
    }
}

/*
  For each received stanza the client might send out packets.
  We should ideally put all the request in the queue and call
  processRequestQueue with a timeOut.
*/ 
- (void)broadcastStanzas:(NSXMLNode *)node
{
    NSUInteger level = [node level];
    while( (node = [node nextNode]) )
    {
        
        if([node level] == level + 1)
        {
            [multicastDelegate transport:self 
                        didReceiveStanza:[(NSXMLElement *)node copy]];
        }
    }
}

#pragma mark -
#pragma mark HTTP Request Response

- (void)handleAttributesInResponse:(NSXMLElement *)parsedResponse
{
    NSXMLNode *typeAttribute = [parsedResponse attributeForName:@"type"];
    if( typeAttribute != nil && [[typeAttribute stringValue] isEqualToString:@"terminate"] ) 
    {
        NSXMLNode *conditionNode = [parsedResponse attributeForName:@"condition"];
        if(conditionNode != nil) 
        {
            NSString *condition = [conditionNode stringValue];
            if( [condition isEqualToString:@"host-unknown"] )
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:HOST_UNKNOWN userInfo:nil];
            else if ( [condition isEqualToString:@"host-gone"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:HOST_GONE userInfo:nil];
            else if( [condition isEqualToString:@"item-not-found"] )
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:ITEM_NOT_FOUND userInfo:nil];
            else if ( [condition isEqualToString:@"policy-violation"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:POLICY_VIOLATION userInfo:nil];
            else if( [condition isEqualToString:@"remote-connection-failed"] )
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:REMOTE_CONNECTION_FAILED userInfo:nil];
            else if ( [condition isEqualToString:@"bad-request"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:BAD_REQUEST userInfo:nil];
            else if( [condition isEqualToString:@"internal-server-error"] )
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:INTERNAL_SERVER_ERROR userInfo:nil];
            else if ( [condition isEqualToString:@"remote-stream-error"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:REMOTE_STREAM_ERROR userInfo:nil];
            else if ( [condition isEqualToString:@"undefined-condition"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:@"BoshTerminateCondition" 
                                                              code:UNDEFINED_CONDITION userInfo:nil];
            else NSAssert( false, @"Terminate Condition Not Valid");
        }
        state = DISCONNECTED;
    }
    else if( !self.sid )
    {
        [self createSessionResponseHandler:parsedResponse];
    }
}

- (void)createSessionResponseHandler:(NSXMLElement *)parsedResponse
{
    NSArray *responseAttributes = [parsedResponse attributes];
    
    /* Setting inactivity, sid, wait, hold, lang, authid, secure, requests */
    for(NSXMLNode *attr in responseAttributes)
    {
        NSString *attrName = [attr name];
        NSString *attrValue = [attr stringValue];
        SEL setter = [self setterForProperty:attrName];
        
        if([self respondsToSelector:setter]) 
        {
            [self performSelector:setter withObject:attrValue];
        }
    }
    
    /* Not doing anything with namespaces right now - because chirkut doesn't send it */
    //NSArray *responseNamespaces = [rootElement namespaces];
    
	state = CONNECTED;
    [multicastDelegate transportDidConnect:self];
    [multicastDelegate transportDidStartNegotiation:self];
}

- (void)handleDisconnection
{
    NSLog(@"disconnectSessionResponseHandler");
    if(self.disconnectError != nil)
    {
        [multicastDelegate transportWillDisconnect:self withError:self.disconnectError];
        [disconnectError_ release];
        self.disconnectError = nil;
    }
    [pendingXMPPStanzas removeAllObjects];
    state = DISCONNECTED;
    [multicastDelegate transportDidDisconnect:self];
}

- (NSXMLElement *)newXMLElementFromData:(NSData *)data 
{
    NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return [[NSXMLElement alloc] initWithXMLString:string error:nil];
}

- (void)processResponses
{
    while ( maxRidProcessed < [boshWindowManager maxRidReceived] ) 
    {
        ++maxRidProcessed;
        RequestResponsePair *pair = [requestResponsePairs objectForLongLongKey:maxRidProcessed];
        NSAssert( [pair response], @"Processing nil response" );
        [self handleAttributesInResponse:[pair response]];
        [self broadcastStanzas:[pair response]];
        [requestResponsePairs removeObjectForLongLongKey:maxRidProcessed];
        if ( state == DISCONNECTED )
        {
            [self handleDisconnection];
        }
    }
}

/* 
 Should call processRequestQueue after some timeOut 
 Handle terminate response sent in any request.
 */
- (void)requestFinished:(ASIHTTPRequest *)request
{
    NSData *responseData = [request responseData];
    NSXMLElement *postBody = [self newXMLElementFromData:[request postBody]];
    long long rid = [self getRidInRequest:postBody];
    
    NSLog(@"BOSH: RECD[%qi] = %@", rid, [request responseString]);
    
    retryCounter = 0;
    NSXMLElement *parsedResponse = [self parseXMLData:responseData];
    if ( !parsedResponse )
    {
        [self requestFailed:request];
        return;
    }
    RequestResponsePair *requestResponsePair = [requestResponsePairs objectForLongLongKey:rid];
    [requestResponsePair setResponse:parsedResponse];
    
    [boshWindowManager recievedResponseForRid:rid];
    [self processResponses];
    
    [self trySendingStanzas];

    [postBody release];
}


/* Not sending terminate request to the server - just disconnecting */
- (void)requestFailed:(ASIHTTPRequest *)request
{
    //if( ![self isConnected] ) return ;
    NSError *error = [request error];
    
    NSLog(@"BOSH: Request Failed[%@", [self logRequestResponse:[request postBody]]);
    NSLog(@"Failure HTTP statusCode = %d, error domain = %@, error code = %d", [request responseStatusCode],[[request error] domain], [[request error] code]);
    
    BOOL shouldReconnect = ([error code] == ASIRequestTimedOutErrorType || [error code] == ASIConnectionFailureErrorType) && 
    ( retryCounter < RETRY_COUNT_LIMIT ) && 
    (state == CONNECTED);
    ++retryCounter;
    if( shouldReconnect ) 
    {
        NSLog(@"Resending the request");
        [self performSelector:@selector(sendHTTPRequestWithBody:) 
                   withObject:[self parseXMLData:[request postBody]] 
                   afterDelay:RETRY_DELAY];
    }
    else 
    {
        NSLog(@"disconnecting due to request failure");
        [multicastDelegate transportWillDisconnect:self withError:error];
        state = DISCONNECTED;
        [self handleDisconnection];
    }
}

- (void)sendHTTPRequestWithBody:(NSXMLElement *)body
{
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:self.url];
    [request setRequestMethod:@"POST"];
    [request setDelegate:self];
    [request setTimeOutSeconds:(self.wait + 4)];
    
    if(body) 
    {
        [request appendPostData:[[body compactXMLString] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    RequestResponsePair *pair = [[RequestResponsePair alloc] initWithRequest:body response:nil];
    [requestResponsePairs setObject:pair forLongLongKey:[self getRidInRequest:body]];
    
    [request startAsynchronous];
    NSLog(@"BOSH: SEND[%@", [self logRequestResponse:[request postBody]]);
    return;
}

#pragma mark -
#pragma mark utilities

- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload 
                                 attributes:(NSMutableDictionary *)attributes 
                                 namespaces:(NSMutableDictionary *)namespaces
{
    attributes = attributes?attributes:[NSMutableDictionary dictionaryWithCapacity:3];
    namespaces = namespaces?namespaces:[NSMutableDictionary dictionaryWithCapacity:1];
    
    /* Adding ack and sid attribute on every outgoing request after sid is created */
	if( self.sid ) 
    {
        [attributes setValue:self.sid forKey:@"sid"];
        long long ack = maxRidProcessed;
        if( ack != nextRidToSend - 1 ) 
        {
            [attributes setValue:[NSString stringWithFormat:@"%qi", ack] forKey:@"ack"];
        }
    }
    else
    {
        [attributes setValue:@"1" forKey:@"ack"];
    }
    
    [attributes setValue:[NSString stringWithFormat:@"%d", nextRidToSend] forKey:@"rid"];
    [namespaces setValue:BODY_NS forKey:@""];
	
    NSXMLElement *body = [[NSXMLElement alloc] initWithName:@"body"];
	
    NSArray *namespaceArray = [self newXMLNodeArrayFromDictionary:namespaces 
                                                           ofType:NAMESPACE_TYPE];
    NSArray *attributesArray = [self newXMLNodeArrayFromDictionary:attributes 
                                                            ofType:ATTR_TYPE];
    [body setNamespaces:namespaceArray];
    [body setAttributes:attributesArray];
	[namespaceArray release];
    [attributesArray release];
    
    if(payload != nil)
    {
        for(NSXMLElement *child in payload)
        {
            [body addChild:[[child copy] autorelease]];
        }
    }
    
    return body;
}

- (long long)getRidInRequest:(NSXMLElement *)body
{
    
    return body && [body attributeForName:@"rid"]?[[[body attributeForName:@"rid"] stringValue] longLongValue]:-1;
}

- (NSXMLElement *)parseXMLString:(NSString *)xml
{
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithXMLString:xml
                                                           options:0 
                                                             error:nil] autorelease];
    return [doc rootElement];
}

- (NSXMLElement *)parseXMLData:(NSData *)xml
{
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithData:xml 
                                                      options:0 
                                                        error:nil] autorelease];
    return [doc rootElement];
}

- (NSArray *)newXMLNodeArrayFromDictionary:(NSDictionary *)dict 
                                    ofType:(XMLNodeType)type
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
    return array;
}

- (long long)generateRid
{
    return (arc4random() % 1000000000LL + 1000000001LL);
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

- (NSString *)logRequestResponse:(NSData *)data
{
    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSXMLElement *ele = [self parseXMLData:data];
    long long rid = [self getRidInRequest:ele];
    return [NSString stringWithFormat:@"%qi] = %@", rid, [dataString autorelease]];
}

- (void)dealloc
{
    [multicastDelegate release];
    [url_ release];
    [domain_ release];
    [myJID_ release];
    [authid release];
    [sid_ release];
    [super dealloc];
}
@end
