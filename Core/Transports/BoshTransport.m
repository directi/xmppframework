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
#import "DDLog.h"

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
        request_ = [request retain];
        response_ = [response retain];
    }
    return self;
}

- (void)dealloc
{
    [request_ release];
    [response_ release];
    [super dealloc];
}

#define kPairRequest	@"request"
#define kPairResponse	@"response"

- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeObject:self.request	forKey:kPairRequest];
	[coder encodeObject:self.response forKey:kPairResponse];
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [super init];
	if (self && coder)
	{
		self.request  = [coder decodeObjectForKey:kPairRequest ];
		self.response = [coder decodeObjectForKey:kPairResponse];
	}
	
	return self;
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

- (void)receivedResponseForRid:(long long)rid
{
    NSAssert2(rid > maxRidReceived, @"Recieving response for rid = %qi where maxRidReceived = %qi", rid, maxRidReceived);
    NSAssert3(rid <= maxRidReceived + windowSize, @"Received response for a request outside the rid window. responseRid = %qi, maxRidReceived = %qi, windowSize = %qi", rid, maxRidReceived, windowSize);
    [receivedRids addLongLong:rid];
    while ( [receivedRids containsLongLong:(maxRidReceived + 1)] )
    {
        ++maxRidReceived;
        [receivedRids removeLongLong:maxRidReceived];
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

#define kMaxRidReceived	@"maxRidReceived"
#define kMaxRidSent		@"maxRidSent"
#define kReceivedRids	@"receivedRids"
#define kWindowSize		@"windowSize"

- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeInt64:maxRidReceived forKey:kMaxRidReceived];
	[coder encodeInt64:maxRidSent forKey:kMaxRidSent];
	[coder encodeObject:receivedRids forKey:kReceivedRids];
	[coder encodeInt:self.windowSize forKey:kWindowSize];
}

- (void)commonInitWithCoder:(NSCoder *)coder
{
	maxRidSent		= [coder decodeInt64ForKey:kMaxRidSent];
	maxRidReceived  = [coder decodeInt64ForKey:kMaxRidReceived];
	receivedRids	= [[coder decodeObjectForKey:kReceivedRids] retain];
	self.windowSize = [coder decodeIntForKey:kWindowSize];
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [super init];
	if (self && coder)
	{
		[self commonInitWithCoder:coder];
	}
	
	return self;
}


@end

static const int RETRY_COUNT_LIMIT = 8;
static const NSTimeInterval RETRY_DELAY = 1.0;
static const NSTimeInterval DELAY_UPPER_LIMIT = 128.0;
static const NSTimeInterval DELAY_EXPONENTIATING_FACTOR = 2.0;
static const NSTimeInterval INITIAL_RETRY_DELAY = 1.0;

static const NSString *CONTENT_TYPE = @"text/xml; charset=utf-8";
static NSString *BODY_NS = @"http://jabber.org/protocol/httpbind";
static const NSString *XMPP_NS = @"urn:xmpp:xbosh";

@interface BoshTransport()
@property (nonatomic, assign) BOOL temporaryDisconnect;
@property (nonatomic, readwrite, assign) NSError *disconnectError;
@property (nonatomic, retain) NSMutableSet *pendingHTTPRequests;

- (void)setInactivityFromString:(NSString *)givenInactivity;
- (void)setSecureFromString:(NSString *)isSecure;
- (void)setRequestsFromString:(NSString *)maxRequests;
- (void)setSidFromString:(NSString *)sid;
- (BOOL)canConnect;
- (void)handleAttributesInResponse:(NSXMLElement *)parsedResponse;
- (void)createSessionResponseHandler:(NSXMLElement *)parsedResponse;
- (void)handleDisconnection;
- (long long)generateRid;
- (long long)getRidFromRequest:(ASIHTTPRequest *)request;
- (SEL)setterForProperty:(NSString *)property;
- (NSNumber *)numberFromString:(NSString *)stringNumber;
- (void)sendHTTPRequestWithBody:(NSXMLElement *)body rid:(long long)rid;
- (void)broadcastStanzas:(NSXMLNode *)node;
- (void)trySendingStanzas;
- (void)makeBodyAndSendHTTPRequestWithPayload:(NSArray *)bodyPayload 
                                   attributes:(NSMutableDictionary *)attributes 
                                   namespaces:(NSMutableDictionary *)namespaces;
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
@synthesize routeProtocol = routeProtocol_;
@synthesize host = host_;
@synthesize port = port_;
@synthesize myJID = myJID_;
@synthesize sid = sid_;
@synthesize url = url_;
@synthesize inactivity;
@synthesize secure;
@synthesize authid;
@synthesize requests;
@synthesize disconnectError = disconnectError_;
@synthesize pendingHTTPRequests = pendingHTTPRequests_;
@synthesize isPaused;
@synthesize temporaryDisconnect = temporaryDisconnect_;

#define BoshVersion @"1.6"

#pragma mark -
#pragma mark Private Accessor Method Implementation

- (void)setSidFromString:(NSString *)sid 
{
    self.sid = sid;
}

- (void)setInactivityFromString:(NSString *)inactivityString
{
    NSNumber *givenInactivity = [self numberFromString:inactivityString];
    inactivity = [givenInactivity unsignedIntValue];
}

- (void)setRequestsFromString:(NSString *)requestsString
{
    NSNumber *maxRequests = [self numberFromString:requestsString];
    [boshWindowManager setWindowSize:[maxRequests unsignedIntValue]];
    requests = [maxRequests unsignedIntValue];
}

- (void)setSecureFromString:(NSString *)isSecure
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
    routeProtocol:(NSString *)routeProtocol
             host:(NSString *)host
             port:(unsigned int)port
{
    return [self initWithUrl:url
                   forDomain:domain
               routeProtocol:routeProtocol
                        host:host
                        port:port
                withDelegate:nil];
}

- (id)initWithUrl:(NSURL *)url
        forDomain:(NSString *)domain
     withDelegate:(id<XMPPTransportDelegate>)delegate
{
    return [self initWithUrl:url
                   forDomain:domain
               routeProtocol:routeProtocol_
                        host:nil
                        port:5222 //Default xmpp port
                withDelegate:delegate];
}

- (id)initWithUrl:(NSURL *)url 
        forDomain:(NSString *)domain
    routeProtocol:(NSString *)routeProtocol
             host:(NSString *)host
             port:(unsigned int)port
     withDelegate:(id<XMPPTransportDelegate>)delegate
{
    self = [super init];
    if(self)
    {		
        boshVersion = BoshVersion;
        lang_ = @"en";
        wait_ = 60.0;
        hold_ = 1;

        nextRidToSend = [self generateRid];
        maxRidProcessed = nextRidToSend - 1;
        
        multicastDelegate = [[MulticastDelegate alloc] init];
        if( delegate != nil ) [multicastDelegate addDelegate:delegate];
		
        sid_ = nil;
        inactivity = 48 * 3600;
        requests = 2;
        url_ = [url retain];

        domain_ = [domain copy];
        
        routeProtocol_ = nil;
        if (routeProtocol != nil) {
            routeProtocol_ = [routeProtocol copy];
        }
        
        host_ = nil;
        if (host != nil) {
          host_ = [host copy];
        }
        port_ = port;
        
        myJID_ = nil;
        state = DISCONNECTED;
        disconnectError_ = nil;
				
        temporaryDisconnect_ = NO;

        /* Keeping a random capacity right now */
        pendingXMPPStanzas = [[NSMutableArray alloc] initWithCapacity:25];
        requestResponsePairs = [[NSMutableDictionary alloc] initWithCapacity:3];
        retryCounter = 0;
        nextRequestDelay = INITIAL_RETRY_DELAY;
        
        pendingHTTPRequests_ = [[NSMutableSet alloc] initWithCapacity:2];
        
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
    if (self.isPaused)
    {
      DDLogError(@"BOSH: Need to be unpaused to connect the stream.");
      return FALSE;
    }
    DDLogInfo(@"BOSH: Connecting to %@ with jid = %@", self.domain, [self.myJID bare]);
    
    if(![self canConnect]) return NO;
    state = CONNECTING;
    [multicastDelegate transportWillConnect:self];
    return [self createSession:error];
}

- (void)restartStream
{
    if (self.isPaused)
    {
      DDLogError(@"BOSH: Need to be unpaused to restart the stream.");
      return;
    }
    if(![self isConnected])
    {
        DDLogError(@"BOSH: Need to be connected to restart the stream.");
        return ;
    }
    DDLogVerbose(@"Bosh: Will Restart Stream");
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"true", @"xmpp:restart", nil];
    NSMutableDictionary *ns = [NSMutableDictionary dictionaryWithObjectsAndKeys:XMPP_NS, @"xmpp", nil];
    [self makeBodyAndSendHTTPRequestWithPayload:nil attributes:attr namespaces:ns];
}

- (void)disconnect
{
    if(state != CONNECTED && state != CONNECTING )
    {
        DDLogError(@"BOSH: Need to be connected to disconnect");
        return;
    }
    DDLogInfo(@"Bosh: Will Terminate Session");
    state = DISCONNECTING;
    [multicastDelegate transportWillDisconnect:self];
    [self trySendingStanzas];
}

- (BOOL)sendStanza:(NSXMLElement *)stanza
{
    if (self.isPaused)
    {
      DDLogError(@"BOSH: Need to unpaused to be able to send stanza");
      return NO;
    }
    if (![self isConnected])
    {
        DDLogError(@"BOSH: Need to be connected to be able to send stanza");
        return NO;
    }
    [multicastDelegate transport:self willSendStanza:stanza];
    [pendingXMPPStanzas addObject:stanza];
    [self trySendingStanzas];
    [multicastDelegate transport:self didSendStanza:stanza];
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

- (void)removeDelegate:(id)delegate
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
        DDLogVerbose(@"@BOSH: Either disconnecting or still connected to the server. Disconnect First.");
        return NO;
    }
    if(!self.domain)
    {
        DDLogVerbose(@"BOSH: Called Connect with specifying the domain");
        return NO;
    }
    if(!self.myJID)
    {
        DDLogVerbose(@"BOSH: Called connect without setting the jid");
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
    [attr setObject:@"en" forKey:@"xml:lang"];
    [attr setObject:@"1.0" forKey:@"xmpp:version"];
    [attr setObject:[NSString stringWithFormat:@"%u", self.inactivity] forKey:@"inactivity"];
    [attr setObject:@"iphone" forKey:@"ua"];
    if (self.host != nil) {
        NSString *route = [NSString stringWithFormat:@"%@:%@:%u", self.routeProtocol, self.host, self.port];
        [attr setObject:route forKey:@"route"];
    }
    
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
    [self sendHTTPRequestWithBody:requestPayload rid:nextRidToSend];
    [boshWindowManager sentRequestForRid:nextRidToSend];
    ++nextRidToSend;
    
    [requestPayload release];
}

- (void)sendTerminateRequestWithPayload:(NSArray *)bodyPayload 
{
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"terminate", @"type", nil];
    [self makeBodyAndSendHTTPRequestWithPayload:bodyPayload attributes:attr namespaces:nil];
}

- (void)trySendingStanzas
{
    if( state != DISCONNECTED && ![boshWindowManager isWindowFull] ) 
    {
        if (state == CONNECTED) {
            if ( [pendingXMPPStanzas count] > 0 || [boshWindowManager isWindowEmpty] )
            {
                [self makeBodyAndSendHTTPRequestWithPayload:pendingXMPPStanzas 
                                                 attributes:nil 
                                                 namespaces:nil];
                [pendingXMPPStanzas removeAllObjects];
            } 
        }
        else if(state == DISCONNECTING) 
        { 
            [self sendTerminateRequestWithPayload:pendingXMPPStanzas];
            [pendingXMPPStanzas removeAllObjects];
            state = TERMINATING;
        }
        else if ([boshWindowManager isWindowEmpty] && state == TERMINATING) 
        {
            /* sending more empty requests till we get a terminate response */
            [self makeBodyAndSendHTTPRequestWithPayload:nil 
                                             attributes:nil 
                                             namespaces:nil];                
        }
    }
}

/*
  For each received stanza the client might send out packets.
  We should ideally put all the request in the queue and call
  processRequestQueue with a timeOut.
*/ 
- (void)broadcastStanzas:(NSXMLNode *)body
{
    while ([body childCount] > 0) {
        NSXMLNode *node = [body childAtIndex:0];
        if ([node isKindOfClass:[NSXMLElement class]]) {
            [node detach];
            [multicastDelegate transport:self didReceiveStanza:(NSXMLElement *)node];
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
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:HOST_UNKNOWN userInfo:nil];
            else if ( [condition isEqualToString:@"host-gone"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:HOST_GONE userInfo:nil];
            else if( [condition isEqualToString:@"item-not-found"] )
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:ITEM_NOT_FOUND userInfo:nil];
            else if ( [condition isEqualToString:@"policy-violation"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:POLICY_VIOLATION userInfo:nil];
            else if( [condition isEqualToString:@"remote-connection-failed"] )
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:REMOTE_CONNECTION_FAILED userInfo:nil];
            else if ( [condition isEqualToString:@"bad-request"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:BAD_REQUEST userInfo:nil];
            else if( [condition isEqualToString:@"internal-server-error"] )
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:INTERNAL_SERVER_ERROR userInfo:nil];
            else if ( [condition isEqualToString:@"remote-stream-error"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
                                                              code:REMOTE_STREAM_ERROR userInfo:nil];
            else if ( [condition isEqualToString:@"undefined-condition"] ) 
                disconnectError_ = [[NSError alloc] initWithDomain:BoshTerminateConditionDomain
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
    
  if ( state == CONNECTING ) {
    state = CONNECTED;
    [multicastDelegate transportDidConnect:self];
    [multicastDelegate transportDidStartNegotiation:self];
  }
}

- (void)handleDisconnection
{
    if(self.disconnectError != nil)
    {
        [multicastDelegate transportWillDisconnect:self withError:self.disconnectError];
        [disconnectError_ release];
        self.disconnectError = nil;
    }
    [pendingXMPPStanzas removeAllObjects];
    state = DISCONNECTED;
    for (ASIHTTPRequest *request in pendingHTTPRequests_) 
    {
        DDLogWarn(@"Cancelling pending request with rid = %qi", [self getRidFromRequest:request]);
        [request clearDelegatesAndCancel];
    }
    [pendingHTTPRequests_ removeAllObjects];
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

- (void)resendRequest:(ASIHTTPRequest *)request
{
    long long rid = [self getRidFromRequest:request];
    [self sendHTTPRequestWithBody:[self parseXMLData:[request postBody]] rid:rid];
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSError *error = [request error];
    long long rid = [self getRidFromRequest:request];
    
#if DEBUG_WARN
    NSString *requestString = [[NSString alloc] initWithData:[request postBody] encoding:NSUTF8StringEncoding];
    DDLogWarn(@"BOSH: Request Failed[%qi] = %@", rid, requestString);
    DDLogWarn(@"Failure HTTP statusCode = %d, error domain = %@, error code = %d", [request responseStatusCode],[[request error] domain], [[request error] code]);
    [requestString release];
#endif
    
    [pendingHTTPRequests_ removeObject:request];
    
    BOOL shouldReconnect = ([error code] == ASIRequestTimedOutErrorType || [error code] == ASIConnectionFailureErrorType) && 
        (state == CONNECTED || state == DISCONNECTING);
    if(shouldReconnect)
    {
        DDLogInfo(@"Resending the request");
        [self performSelector:@selector(resendRequest:) 
                   withObject:request 
                   afterDelay:nextRequestDelay];
        [multicastDelegate transport:self willReconnectInTime:nextRequestDelay+self.wait];
        self.temporaryDisconnect = YES;

        if (retryCounter < RETRY_COUNT_LIMIT) {
            ++retryCounter;
            nextRequestDelay *= DELAY_EXPONENTIATING_FACTOR;
				}
    }
    else 
    {
        DDLogWarn(@"disconnecting due to request failure");
        if (error == nil) {
            error = [[[NSError alloc] initWithDomain:BoshTerminateConditionDomain 
                                                code:UNDEFINED_CONDITION 
                                            userInfo:nil] autorelease];
        }
        [multicastDelegate transportWillDisconnect:self withError:error];
        state = DISCONNECTED;
        [self handleDisconnection];
    }
}

/* 
 Should call processRequestQueue after some timeOut 
 Handle terminate response sent in any request.
 */
- (void)requestFinished:(ASIHTTPRequest *)request
{
    long long rid = [self getRidFromRequest:request];
    DDLogRecvPre(@"BOSH: RECD[%qi] = %@", rid, [request responseString]);
    NSData *responseData = [request responseData];
    
    NSXMLElement *parsedResponse = [self parseXMLData:responseData];
    
    if (!parsedResponse || parsedResponse.kind != DDXMLElementKind || 
        ![parsedResponse.name isEqualToString:@"body"]  || 
        ![[parsedResponse namespaceStringValueForPrefix:@""] isEqualToString:BODY_NS])
    {
        [self requestFailed:request];
        return;
    }
    
    if (self.temporaryDisconnect)
    {
        self.temporaryDisconnect = NO;
        [multicastDelegate transportDidReconnect:self];
    }
		
    retryCounter = 0;
    nextRequestDelay = INITIAL_RETRY_DELAY;
    
    RequestResponsePair *requestResponsePair = [requestResponsePairs objectForLongLongKey:rid];
    [requestResponsePair setResponse:parsedResponse];
    
    [pendingHTTPRequests_ removeObject:request];
    
    [boshWindowManager receivedResponseForRid:rid];
    [self processResponses];
    
    [self trySendingStanzas];
}

- (void)sendHTTPRequestWithBody:(NSXMLElement *)body rid:(long long)rid
{
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:self.url];
    [request setRequestMethod:@"POST"];
    [request setDelegate:self];
    [request setTimeOutSeconds:(self.wait + 4)];
    request.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:rid]
                                                   forKey:@"rid"];
    if(body) 
    {
        [request appendPostData:[[body compactXMLString] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    RequestResponsePair *pair = [[RequestResponsePair alloc] initWithRequest:body response:nil];
    [requestResponsePairs setObject:pair forLongLongKey:rid];
    [pair release];
    
    [pendingHTTPRequests_ addObject:request];
    
    [request startAsynchronous];
    DDLogSend(@"BOSH: SEND[%qi] = %@", rid, body);
    return;
}

#pragma mark -
#pragma mark utilities

- (long long)getRidFromRequest:(ASIHTTPRequest *)request
{
    return [[[request userInfo] objectForKey:@"rid"] longLongValue];
}

- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload 
                                 attributes:(NSMutableDictionary *)attributes 
                                 namespaces:(NSMutableDictionary *)namespaces
{
    attributes = attributes ? attributes : [NSMutableDictionary dictionaryWithCapacity:3];
    namespaces = namespaces ? namespaces : [NSMutableDictionary dictionaryWithCapacity:1];
    
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
            [body addChild:child];
        }
    }
    
    return body;
}

- (NSXMLElement *)parseXMLString:(NSString *)xml
{
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithXMLString:xml
                                                           options:0
                                                             error:NULL] autorelease];
    NSXMLElement *element = [doc rootElement];
    [element detach];
    return element;
}

- (NSXMLElement *)parseXMLData:(NSData *)xml
{
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithData:xml 
                                                      options:0 
                                                        error:NULL] autorelease];
    NSXMLElement *element = [doc rootElement];
    [element detach];
    return element;
}

- (NSArray *)newXMLNodeArrayFromDictionary:(NSDictionary *)dict 
                                    ofType:(XMLNodeType)type
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (NSString *key in dict) 
    {
        NSString *value = [dict objectForKey:key];
        NSXMLNode *node;
        
        if(type == ATTR_TYPE) 
        {
            node = [NSXMLNode attributeWithName:key stringValue:value];
        }
        else if(type == NAMESPACE_TYPE)
        {
            node = [NSXMLNode namespaceWithName:key stringValue:value];
        }
        else
        {
            NSException *exception = [NSException exceptionWithName:@"InvalidXMLNodeType"
                                                             reason:@"BOSH: Wrong Type Passed to createArrayFrom Dictionary"
                                                           userInfo:nil];
            @throw exception;
        }
		
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
    setter = [setter stringByAppendingString:@"FromString:"];
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
    for (ASIHTTPRequest *request in pendingHTTPRequests_) 
    {
      DDLogWarn(@"Cancelling pending request with rid = %qi", [self getRidFromRequest:request]);
      [request clearDelegatesAndCancel];
    }
    [lang_ release];
    [pendingHTTPRequests_ removeAllObjects];
    [pendingHTTPRequests_ release];
    
    [multicastDelegate release];
    [url_ release];
    [domain_ release];
    [routeProtocol_ release];
    [host_ release];
    [myJID_ release];
    [authid release];
    [sid_ release];
    [boshWindowManager release];
    [pendingXMPPStanzas release];
    [requestResponsePairs release];
    [super dealloc];
}

#pragma mark Protocol NSCoding Method Implementation

#define kNextRidToSend		@"nextRidToSend"
#define kMaxRidProcessed	@"maxRidProcessed"

#define kPendingXMPPStanza	@"pendingXMPPStanzas"
#define kBoshWindowManager	@"boshWindowManager"
#define kState				@"state"

#define kRequestResponsePairs @"requestResponsePairs"

#define kDisconnectError_	@"disconnectError_"

#define kRetryCounter		@"retryCounter"
#define kNextRequestDelay	@"nextRequestDelay"

#define kMyJID			@"myJID"
#define kWait			@"wait"
#define kHold			@"hold"
#define kLang			@"lang"
#define kDomain			@"domain"
#define kRouteProtocol	@"routeProtocol"
#define kHost			@"host"
#define kPort			@"port"
#define kInactivity		@"inactivity"
#define kSecure			@"secure"
#define kRequest		@"requests"
#define kAuthId			@"authid"
#define kSid			@"sid"
#define kUrl			@"url"
#define kPersistedCookies  @"persistedCookies"


- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeInt64:nextRidToSend forKey:kNextRidToSend];
	[coder encodeInt64:maxRidProcessed forKey:kMaxRidProcessed];
	
	[coder encodeObject:pendingXMPPStanzas forKey:kPendingXMPPStanza];
	[coder encodeObject:boshWindowManager forKey:kBoshWindowManager] ;
	[coder encodeInt:state forKey:kState];
	
	[coder encodeObject:requestResponsePairs forKey:kRequestResponsePairs];
	
	[coder encodeObject:disconnectError_ forKey:kDisconnectError_];
	
	[coder encodeInt:retryCounter  forKey:kRetryCounter];
	[coder encodeDouble:nextRequestDelay forKey:kNextRequestDelay];
	
	[coder encodeObject:self.myJID forKey:kMyJID];
	[coder encodeInt:self.wait forKey:kWait];
	[coder encodeInt:self.hold forKey:kHold];
	[coder encodeObject:self.lang forKey:kLang];
	[coder encodeObject:self.domain forKey:kDomain];
	[coder encodeObject:self.routeProtocol forKey:kRouteProtocol];
	[coder encodeObject:self.host forKey:kHost];
	[coder encodeInt:self.port forKey:kPort];
	[coder encodeInt:self.inactivity forKey:kInactivity];
	[coder encodeBool:self.secure forKey:kSecure];
	[coder encodeInt:self.requests forKey:kRequest];
	[coder encodeObject:self.authid forKey:kAuthId];
	[coder encodeObject:self.sid forKey:kSid];
	[coder encodeObject:self.url forKey:kUrl];

    [coder encodeObject:[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies] forKey:kPersistedCookies];
}

- (void)commonInitWithCoder:(NSCoder *)coder
{
	boshVersion = BoshVersion;
	
	nextRidToSend = [coder decodeInt64ForKey:kNextRidToSend];
	maxRidProcessed = [coder decodeInt64ForKey:kMaxRidProcessed];
	
	pendingXMPPStanzas =[[coder decodeObjectForKey:kPendingXMPPStanza] retain];
	boshWindowManager = [[coder decodeObjectForKey:kBoshWindowManager] retain];
	state = [coder decodeIntForKey:kState];
	
	requestResponsePairs = [[coder decodeObjectForKey:kRequestResponsePairs] retain];
	
	disconnectError_ = [[coder decodeObjectForKey:kDisconnectError_] retain];
	
	retryCounter = [coder decodeIntForKey:kRetryCounter];
	nextRequestDelay= [coder decodeDoubleForKey:kNextRequestDelay];
	
	
	self.myJID= [coder decodeObjectForKey:kMyJID];
	self.wait= [coder decodeIntForKey:kWait];
	self.hold= [coder decodeIntForKey:kHold];
	self.lang= [coder decodeObjectForKey:kLang];
	self.domain= [coder decodeObjectForKey:kDomain];
	self.routeProtocol= [coder decodeObjectForKey:kRouteProtocol];
	self.host= [coder decodeObjectForKey:kHost];
	self.port= [coder decodeIntForKey:kPort];
	self.inactivity= [coder decodeIntForKey:kInactivity];
	secure = [coder decodeBoolForKey:kSecure];
	requests = [coder decodeIntForKey:kRequest];
	self.authid= [coder decodeObjectForKey:kAuthId];
	self.sid= [coder decodeObjectForKey:kSid];
	self.url= [coder decodeObjectForKey:kUrl];
	
	pendingHTTPRequests_ = [[NSMutableSet alloc] initWithCapacity:2];

	for ( NSHTTPCookie *cookie in [coder decodeObjectForKey:kPersistedCookies] ) 
	{
		[[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
	}

	multicastDelegate = [[MulticastDelegate alloc] init];
	
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [super init];
	if (self && coder)
	{
		[self commonInitWithCoder:coder];
	}
	return self;
}

/*
 * This method to be called after the uncompression of the transport object.
 * It looks for packets in requestResponsePairs without a response and sends them.
 */
- (void)resendRemainingRequests
{
	BOOL didSendSomething = NO;
	for ( NSNumber *ridNumber in [requestResponsePairs allKeys ])
	{ 
		long long rid = [ridNumber longLongValue];
		RequestResponsePair *pair = [requestResponsePairs objectForLongLongKey:rid];
		if ( !pair.response )
		{
			didSendSomething = YES;
			[self sendHTTPRequestWithBody:pair.request rid:rid];
		}
	}
	
	if ( !didSendSomething )
	{
		// if we havent sent anything, send an empty packet.
		[self trySendingStanzas];
	}
}

- (BOOL)supportsPause {
	return YES;
}

- (void)pause
{
	isPaused = true;
	
	for (ASIHTTPRequest *request in pendingHTTPRequests_) 
	{
		DDLogWarn(@"Cancelling pending request with rid = %qi", [self getRidFromRequest:request]);
		[request clearDelegatesAndCancel];
	}
	[pendingHTTPRequests_ removeAllObjects];
}

- (void)resume
{
	isPaused = false;
	
	[self resendRemainingRequests];
}


@end
