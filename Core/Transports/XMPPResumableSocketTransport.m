
#import "XMPPResumableSocketTransport.h"
#import "AsyncSocket.h"

@implementation StanzaWithTag

@synthesize stanza;
@synthesize tag;

- (id) initWithStanzaInStringFormat:(NSString *)element withTag:(int)initTag
{
	if ( (self=[super init]))
	{
		stanza = [element retain];
		
		tag = initTag;
	}
	return self;
}

#define kStanza @"Stanza"
#define kTag    @"Tag"
- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeObject:stanza forKey:kStanza];
	[coder encodeInt:tag forKey:kTag];
}

- (id)initWithCoder: (NSCoder *)coder
{
	if ( (self = [super init]) )
	{
		stanza  = [[coder decodeObjectForKey:kStanza] retain];
		tag     = [coder decodeIntForKey:kTag];  
	}
	return self;
}

- (void) dealloc
{
	[stanza release];
	[super dealloc];
}

@end

@implementation AcknowledgementQueue

- (id)init
{
	self = [super init];
	if (self)
	{
		stanzaQueue = [[NSMutableArray  array] retain];
	}
	return self;
}

- (void)dealloc
{
	[stanzaQueue release];
	[super dealloc];
}

#define kStanzaQueue @"StanzaQueue"
- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeObject:stanzaQueue forKey:kStanzaQueue];
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [super init];
	if (self)
	{
		stanzaQueue = [[coder decodeObjectForKey:kStanzaQueue] retain];
	}
	return self;
}

/////////////////////////////////////////
#pragma mark stanza Queue Methods
/////////////////////////////////////////

- (void) enqueueStanza:(NSString *)element withTag:(int)tag
{
	StanzaWithTag *stanzaQueueObject = [[StanzaWithTag alloc] initWithStanzaInStringFormat:element withTag:tag];
	
	// inserting at top of the queue
	[stanzaQueue insertObject:stanzaQueueObject atIndex:0];
	[stanzaQueueObject release];
	
}

- (void) dequeueStanzasTillTag:(int) maxTag
{
	StanzaWithTag *stanzaQueueObject = [stanzaQueue lastObject];
	while( stanzaQueueObject.tag <= maxTag && [stanzaQueue count]>0)
	{
		[stanzaQueue removeLastObject];
		stanzaQueueObject = [stanzaQueue lastObject];
	}
}

- (NSArray *) stanzas
{
	NSMutableArray *stanzaList = [NSMutableArray array ];
	StanzaWithTag *stanzaQueueObject;
	for ( stanzaQueueObject in stanzaQueue )
	{
		[stanzaList addObject:stanzaQueueObject.stanza];
	}
	return stanzaList;
}
@end

@interface   XMPPSocketTransport (internalMethods) 
- (void)commonInitWithCoder:(NSCoder *)coder;
- (void)sendOpeningXMLString;
- (void)readDataOnAsyncSocket;
- (void)xmppParser:(XMPPParser *)sender didReadElement:(NSXMLElement *)element;
- (void)onSocket:(AsyncSocket *)socket didConnectToHost:(NSString *)givenHost port:(UInt16)givenPort;
- (void)onSocketDidDisconnect:(AsyncSocket *)sock;
- (void)xmppParser:(XMPPParser *)sender didReadRoot:(NSXMLElement *)root;

@end

static const int RETRY_COUNT_LIMIT = 25;
static const NSTimeInterval DELAY_UPPER_LIMIT = 128.0;
static const NSTimeInterval DELAY_EXPONENTIATING_FACTOR = 2.0;
static const NSTimeInterval INITIAL_RETRY_DELAY = 1.0;

@interface XMPPResumableSocketTransport () 

- (void)requestToAcknowledgeStanzas;
- (void)handleStanzaAcknowledgement:(NSXMLElement *)response;
- (void)acknowledgeReceivedStanzas:(NSXMLElement *)response ;

- (void)reconnectSocket;

@end

@implementation XMPPResumableSocketTransport

- (void)commonInit
{
	brokenStream_ = false;
	streamTagClosed = false;
	
	sequenceNumberServer_ = 0;
	sequenceNumberClient_ = 0;
	
	acknowledgementQueue = [[AcknowledgementQueue alloc] init];
	
	retryCounter = 0;
	nextRequestDelay = INITIAL_RETRY_DELAY;
}

- (id)init
{
	self = [super init];
	if (self)
	{
		[self commonInit];
	}
	return self;
}

- (id)initWithHost:(NSString *)givenHost port:(UInt16)givenPort
{
	self = [super initWithHost:givenHost port:givenPort];
	if (self)
	{
		[self commonInit];
	}
	return self;
}


- (void)dealloc
{
	[acknowledgementQueue release];
	[super dealloc];
}

/////////////////////////////////////////
#pragma mark NSCoding Methods
/////////////////////////////////////////

#define kBrokenStream @"BrokenStream"           // BOOL brokenStream_;
#define kTerminatedWithError @"TerminatedWithError"
#define kSequenceServer @"ServerStanzaSequence" //int sequenceNumberServer_;
#define kSequenceClient @"ClientStanzaSequence" //int sequenceNumberClient_;

#define kAcknowledgementQueue @"AcknowledgementQueue" //AcknowledgementQueue *acknowledgementQueue;

#define kRetryCounter @"retryCounter"
#define kNextRequestDelay @"nextRequestDelay"


- (void)commonInitWithCoder:(NSCoder *)coder
{
	brokenStream_         = [coder decodeBoolForKey:kBrokenStream];
	streamTagClosed      = [coder decodeBoolForKey:kTerminatedWithError];
	sequenceNumberServer_ = [coder decodeIntForKey:kSequenceServer];
	sequenceNumberClient_ = [coder decodeIntForKey:kSequenceClient];
	acknowledgementQueue  = [[coder decodeObjectForKey:kAcknowledgementQueue] retain];
	
	retryCounter          = [coder decodeIntForKey:kRetryCounter];
	nextRequestDelay      = [coder decodeIntForKey:kNextRequestDelay];
}
- (void)encodeWithCoder: (NSCoder *)coder
{
	[super encodeWithCoder:coder];
	
	[coder encodeBool:brokenStream_ forKey:kBrokenStream ];
	[coder encodeBool:streamTagClosed forKey:kTerminatedWithError ];
	[coder encodeInt:sequenceNumberClient_ forKey:kSequenceClient];
	[coder encodeInt:sequenceNumberServer_ forKey:kSequenceServer];
	[coder encodeObject:acknowledgementQueue forKey:kAcknowledgementQueue];
	
	[coder encodeInt:retryCounter forKey:kRetryCounter];
	[coder encodeInt:nextRequestDelay forKey:kNextRequestDelay];
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self)
	{
		[self commonInitWithCoder:coder];
	}
	return self;
}

- (void)resendRemainingRequests
{
	// we will send all unacked requests once we receive ack-count from server.
	// for the time, we would simply connect.
	// Also, as this function has to be called only in case of resuming previous session, assume the stream to be broken
	if (!streamTagClosed)
	{
		brokenStream_ = true;
		retryCounter = 0;
		nextRequestDelay = INITIAL_RETRY_DELAY;

		[self reconnectSocket];
	}
}
/////////////////////////////////////////
#pragma mark XMPP Stanza Acknowledgement
/////////////////////////////////////////

/*
 This method requests the server to send acknowledgement of received stanzas
 */

- (void)requestToAcknowledgeStanzas{
	NSXMLElement *request = [NSXMLElement elementWithName:@"r" 
													xmlns:@"urn:tcp-proxy"];
	[self sendStanza:request];
}

/*
 * acknowledgement received for sent stanzas. Clear them from ackQueue
 */
- (void)handleStanzaAcknowledgement:(NSXMLElement *)response {
	
	NSInteger receivedSequenceNumber = [[response attributeNumberIntValueForName:@"h"] intValue];
	[acknowledgementQueue dequeueStanzasTillTag:receivedSequenceNumber];
}

/*
 * acknowledge received stanzas. 
 */
- (void)acknowledgeReceivedStanzas:(NSXMLElement *)response {
	
	NSXMLElement *acknowledgement = [NSXMLElement elementWithName:@"a" 
															xmlns:@"urn:tcp-proxy"];
	[acknowledgement addAttributeWithName:@"v" stringValue: [NSString stringWithFormat:@"%d", sequenceNumberServer_ ]];
	[self sendStanza:acknowledgement];
}

#pragma mark - internal methods
- (void)sendResumingStream
{
    [self sendOpeningXMLString];
	
    NSString *temp = @"<stream:stream xmlns=\"%@\" xmlns:stream=\"%@\" version='1.0' sid='%@' ack='%d' from='%@'/>";
    NSString *s2 = [NSString stringWithFormat:temp, @"jabber:client", @"http://etherx.jabber.org/streams", self.sid,sequenceNumberServer_, [myJID bare] ];
    [super sendStanzaWithString:s2];
}

#pragma mark - Socket reconnection methods

- (void)attemptReconnectSocket
{
	if (retryCounter < RETRY_COUNT_LIMIT )
	{
		NSLog(@"Resending the request after delay of %f",nextRequestDelay);
		[self performSelector:@selector(reconnectSocket) 
				   withObject:nil 
				   afterDelay:nextRequestDelay];
		++retryCounter;
		nextRequestDelay = nextRequestDelay>DELAY_UPPER_LIMIT ? nextRequestDelay : nextRequestDelay*DELAY_EXPONENTIATING_FACTOR;
	}
}

- (void)cancelReconnectSocket
{
	if ( retryCounter != 0 )
	{
		NSLog(@"Cancel reconnect to Socket ");
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reconnectSocket) object:nil];
		retryCounter = 0;
		nextRequestDelay = INITIAL_RETRY_DELAY;
	}
}

- (void)reconnectSocket
{
	NSLog(@"Attempting reconnect...");
	[asyncSocket release];
	asyncSocket = nil;
	
	NSError *errPtr = nil;
	asyncSocket = [[AsyncSocket alloc] initWithDelegate:self];
	[asyncSocket connectToHost:host onPort:port error:&errPtr];
	if (errPtr)
	{
		[self attemptReconnectSocket];
	}
}

#pragma mark - Overridden Transport methods
//
- (void)xmppParser:(XMPPParser *)sender didReadElement:(NSXMLElement *)element
{
	NSString *elementName = [element name];
	DDLogRecvPost(@"RECV: %@", [element compactXMLString]);
	
	if ( [elementName isEqualToString:@"error"] )
	{
		if ( [[[[element children] objectAtIndex:0] stringValue] isEqualToString:@"Invalid sid"] )
		{
			// the sid we have used is wrong,. need to reattempt login
			streamTagClosed = true;
			
			
			// server has been disconnected. implying that our transport is disconnected as well.
			
			// after sending this stanza, server also disconnects socket,
			// but since parser-methods are on different thread, 
			// order between these cant be ensured. 
			// still, as both of these methods are on same thread (streamThread), these wont be running in parallel in any case.
			
			// if 'onSocketDidDisconnect' has been called before this method, (incrementing retryCount) we should cancel reconnect and send delegates transportDidDisconnect.
			if ( retryCounter != 0 )
			{
				[self cancelReconnectSocket];
				[multicastDelegate transportDidDisconnect:self]; 
			}
			
			return;
		}    
	}
	else if ([elementName isEqualToString:@"a"])
	{
		[self handleStanzaAcknowledgement:element];
		return;
	}
	else if ([elementName isEqualToString:@"r"])
	{
		[self acknowledgeReceivedStanzas:element];
		return;
	}
	
	// Recieved some regular stanza
	//  increment the stanza count
	//  since we have not handled the element itself, must call super method;
	sequenceNumberServer_++;
	[super xmppParser:sender didReadElement:element];
	
}

- (void)xmppParser:(XMPPParser *)sender didReadRoot:(NSXMLElement *)root
{
	if ( brokenStream_ )
	{
		int ackCount = [root attributeIntValueForName:@"ack"] ;
		[acknowledgementQueue dequeueStanzasTillTag:ackCount];
		// send remaining stanzas in acknowledgement queue
		for ( NSXMLElement * stanza in [acknowledgementQueue stanzas])
		{
			[super sendStanza:stanza];
		}
		
		brokenStream_ = false;
	}
	else
	{
		[super xmppParser:sender didReadRoot:root];
	}
}


- (BOOL)sendStanzaWithString:(NSString *)stanza
{
	++sequenceNumberClient_;
	[acknowledgementQueue enqueueStanza:stanza withTag:sequenceNumberClient_];
	if ( sequenceNumberClient_ % 10 == 1 && sequenceNumberClient_ > 10)
	{
		[self requestToAcknowledgeStanzas];
	}
	return [super sendStanzaWithString:stanza];
}


/* disconnect was called with sending </stream:stream>. So stream is not broken */
/*
 * This Method is called on disconnect in transport.
 * If the stream is connected, then it is an explicit logout from the user.
 *    Therefore, the stream is not broken, but cleanly closed.
 * Otherwise, (when xmppStream is not connected), 
 *    then xmppStream is still negociating with server, and so leave xmppStreams previous state. 
 */

- (void)disconnect
{
	streamTagClosed = true;
	[super disconnect];
}



#pragma mark - Overriden Socket Delegate methods

- (void)onSocket:(AsyncSocket *)socket didConnectToHost:(NSString *)givenHost port:(UInt16)givenPort
{
	/*
	 transport socket has been connected.
	 Now if the stream was broken, we should continue with previous stream, by sending stream:stream with sid and ack
	 */
	
    if ( brokenStream_ )
    {
		// if we are reconnected, reset the reconnect count
		retryCounter = 0;
		nextRequestDelay = INITIAL_RETRY_DELAY;
		
		[self sendResumingStream];
		[self readDataOnAsyncSocket];
		[multicastDelegate transportDidReconnect:self];
		brokenStream_ = false;
		streamTagClosed = false;
    }
    else
    {
		[super onSocket:socket didConnectToHost:givenHost port:givenPort];
    }
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	if ( !streamTagClosed)
	{
		brokenStream_ = true; 
		
		// notify delegate for temporaryDisconnect
		[multicastDelegate transportWillReconnect:self];
		
		// Socket has disconnected, so we should try to connect it again after a while.
		[self attemptReconnectSocket];
	}
	else
	{
		[super onSocketDidDisconnect:sock];
	}
}



@end