#import "XMPPStream.h"
#import "AsyncSocket.h"
#import "MulticastDelegate.h"
#import "RFSRVResolver.h"
#import "XMPPParser.h"
#import "XMPPJID.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import "XMPPPresence.h"
#import "XMPPModule.h"
#import "NSDataAdditions.h"
#import "NSXMLElementAdditions.h"

#if TARGET_OS_IPHONE
  // Note: You may need to add the CFNetwork Framework to your project
  #import <CFNetwork/CFNetwork.h>
#endif


NSString *const XMPPStreamErrorDomain = @"XMPPStreamErrorDomain";

enum XMPPStreamFlags
{
	kP2PMode                      = 1 << 0,  // If set, the XMPPStream was initialized in P2P mode
	kP2PInitiator                 = 1 << 1,  // If set, we are the P2P initializer
	kIsSecure                     = 1 << 2,  // If set, connection has been secured via SSL/TLS
	kIsAuthenticated              = 1 << 3,  // If set, authentication has succeeded
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface XMPPDigestAuthentication : NSObject
{
	NSString *rspauth;
	NSString *realm;
	NSString *nonce;
	NSString *qop;
	NSString *username;
	NSString *password;
	NSString *cnonce;
	NSString *nc;
	NSString *digestURI;
}

- (id)initWithChallenge:(NSXMLElement *)challenge;

- (NSString *)rspauth;

- (NSString *)realm;
- (void)setRealm:(NSString *)realm;

- (void)setDigestURI:(NSString *)digestURI;

- (void)setUsername:(NSString *)username password:(NSString *)password;

- (NSString *)response;
- (NSString *)base64EncodedFullResponse;

@end

@interface XMPPStream (PrivateAPI)

- (void)setIsSecure:(BOOL)flag;
- (void)setupKeepAliveTimer;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPStream

@synthesize myJID;
@synthesize remoteJID;
@synthesize myPresence;
@synthesize registeredModules;
@synthesize tag = userTag;

@synthesize customAuthTarget;
@synthesize customAuthSelector;
@synthesize customHandleAuthSelector;

@dynamic transport;

- (void)setTransport:(id<XMPPTransportProtocol>)givenTransport
{
	transport = [givenTransport retain];
	[transport addDelegate:self];
}

- (id)transport
{
	return transport;
}
/**
 * Shared initialization between the various init methods.
**/
- (void)commonInit
{
	multicastDelegate = [[MulticastDelegate alloc] init];
	
	state = STATE_DISCONNECTED;
	
	registeredModules = [[MulticastDelegate alloc] init];
	autoDelegateDict = [[NSMutableDictionary alloc] init];
}

- (id)initWithTransport:(id<XMPPTransportProtocol>)givenTransport
{
    if ((self = [super init]))
    {
        [self commonInit];
        [self setTransport:givenTransport];
    }
    return self;
}

- (id)initWithP2PTransport:(id<XMPPTransportProtocol>)givenTransport
{
    if ((self = [self initWithTransport:givenTransport]))
    {
        flags = kP2PMode;
    }
    return self;
}

- (NSXMLElement *)newRootElement
{
    NSString *streamNamespaceURI = @"http://etherx.jabber.org/streams";
    NSXMLElement *element = [[NSXMLElement alloc] initWithName:@"stream" URI:streamNamespaceURI];
    [element addNamespaceWithPrefix:@"stream" stringValue:streamNamespaceURI];
    [element addNamespaceWithPrefix:@"" stringValue:@"jabber:client"];
    return element;
}

/**
 * Standard deallocation method.
 * Every object variable declared in the header file should be released here.
**/
- (void)dealloc
{
	[transport release];
	[multicastDelegate release];
	
	[tempPassword release];
	
	[myJID release];
	[remoteJID release];
	
	[myPresence release];
	[rootElement release];
	
	[registeredModules release];
	[autoDelegateDict release];
	
    [userTag release];
  
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding Protocol methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define kState			@"state"

#define kFlags			@"flags"

#define kTempPassword	@"tempPassword"

#define kMyJID			@"myJID"
#define kRemoteJID		@"remoteJID"

#define kMYPresence		@"myPresence"
#define	kRootelement	@"rootElement"

//#define @"id userTag" not being used ryt now in the code, therefore not using
//
//#define @"id customAuthTarget"
//#define @"SEL customAuthSelector"
//#define @"SEL customHandleAuthSelector"

- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeInt:state forKey:kState];
	[coder encodeInt:flags forKey:kFlags];
	[coder encodeObject:tempPassword forKey:kTempPassword];
	[coder encodeObject:myJID forKey:kMyJID];
	[coder encodeObject:remoteJID forKey:kRemoteJID];
	
	[coder encodeObject:myPresence  forKey:kMYPresence];
	[coder encodeObject:rootElement forKey:kRootelement];
}

- (void)commonInitWithCoder:(NSCoder *)coder
{
	state = [coder decodeIntForKey:kState];
	flags = (Byte) [coder decodeIntForKey:kFlags];
	
	tempPassword    = [[coder decodeObjectForKey:kTempPassword] copy];
	myJID      = [[coder decodeObjectForKey:kMyJID] copy];
	remoteJID  = [[coder decodeObjectForKey:kRemoteJID] copy] ;
	
	myPresence  = [[coder decodeObjectForKey:kMYPresence]  retain];
	rootElement = [[coder decodeObjectForKey:kRootelement] retain];
	
	multicastDelegate = [[MulticastDelegate alloc] init];
	registeredModules = [[MulticastDelegate alloc] init];
	autoDelegateDict  = [[NSMutableDictionary alloc] init];
	
}

- (id)initWithCoder: (NSCoder *)coder
{
	self = [self init];
	if (self && coder)
	{
		[self commonInitWithCoder:coder];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)addDelegate:(id)delegate
{
	[multicastDelegate addDelegate:delegate];
}

- (void)removeDelegate:(id)delegate
{
	[multicastDelegate removeDelegate:delegate];
}

/**
 * Returns YES if the stream was opened in P2P mode.
 * In other words, the stream was created via initP2PFrom: to use XEP-0174.
**/
- (BOOL)isP2P
{
    return (flags & kP2PMode) ? YES : NO;
}

- (BOOL)isP2PRecipient
{
    if (flags & kP2PMode)
    {
        return [transport isP2PRecipient];
    }
    return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection State
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if the connection is closed, and thus no stream is open.
 * If the stream is neither disconnected, nor connected, then a connection is currently being established.
**/
- (BOOL)isDisconnected
{
	return (state == STATE_DISCONNECTED);
}

/**
 * Returns YES if the connection is open, and the stream has been properly established.
 * If the stream is neither disconnected, nor connected, then a connection is currently being established.
**/
- (BOOL)isConnected
{
	return (state == STATE_CONNECTED);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark C2S Connection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)connect:(NSError **)errPtr
{
	if (state > STATE_DISCONNECTED)
	{
		if (errPtr)
		{
			NSString *errMsg = @"Attempting to connect while already connected or connecting.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidState userInfo:info];
		}
		return NO;
	}
	
	if (myJID == nil)
	{
		// Note: If you wish to use anonymous authentication, you should still set myJID prior to calling connect.
		// You can simply set it to something like "anonymous@<domain>", where "<domain>" is the proper domain.
		// After the authentication process, you can query the myJID property to see what your assigned JID is.
		// 
		// Setting myJID allows the framework to follow the xmpp protocol properly,
		// and it allows the framework to connect to servers without a DNS entry.
		// 
		// For example, one may setup a private xmpp server for internal testing on their local network.
		// The xmpp domain of the server may be something like "testing.mycompany.com",
		// but since the server is internal, an IP (192.168.1.22) is used as the hostname to connect.
		// 
		// Proper connection requires a TCP connection to the IP (192.168.1.22),
		// but the xmpp handshake requires the xmpp domain (testing.mycompany.com).
		
		if (errPtr)
		{
			NSString *errMsg = @"You must set myJID before calling connect.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidProperty userInfo:info];
		}
		return NO;
	}

    // Notify delegates
    [multicastDelegate xmppStreamWillConnect:self];

    // Instruct transport to open the connection
    if (myJID)
    {
        [transport setMyJID:myJID];
    }
    if ([self isP2P] && remoteJID)
    {
        [transport setRemoteJID:remoteJID];
    }
    BOOL result = [transport connect:errPtr];
    state = STATE_OPENING;
    return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Disconnect
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Closes the connection to the remote host.
**/
- (void)disconnect
{
    // FIXME: this method should be synchronous
	[multicastDelegate xmppStreamWasToldToDisconnect:self];
	[transport disconnect];
	
	// Note: The state is updated automatically in the onSocketDidDisconnect: method.
}

- (void)disconnectAfterSending
{
	[multicastDelegate xmppStreamWasToldToDisconnect:self];
	[transport disconnect];
	
	// Note: The state is updated automatically in the onSocketDidDisconnect: method.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Security
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if SSL/TLS has been used to secure the connection.
**/
- (BOOL)isSecure
{
	return (flags & kIsSecure) ? YES : NO;
}
- (void)setIsSecure:(BOOL)flag
{
	if(flag)
		flags |= kIsSecure;
	else
		flags &= ~kIsSecure;
}

- (BOOL)supportsStartTLS
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	//stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		NSXMLElement *starttls = [features elementForName:@"starttls" xmlns:@"urn:ietf:params:xml:ns:xmpp-tls"];
		
		return (starttls != nil);
	}
	return NO;
}

- (void)sendStartTLSRequest
{
	NSString *starttls = @"<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>";
	[transport sendStanzaWithString:starttls];
}

- (BOOL)secureConnection:(NSError **)errPtr
{
	if (state != STATE_CONNECTED)
	{
		if (errPtr)
		{
			NSString *errMsg = @"Please wait until the stream is connected.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidState userInfo:info];
		}
		return NO;
	}
	
	if (![self supportsStartTLS])
	{
		if (errPtr)
		{
			NSString *errMsg = @"The server does not support startTLS.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamUnsupportedAction userInfo:info];
		}
		return NO;
	}
	
	// Update state
	state = STATE_STARTTLS;
	
	// Send the startTLS XML request
	[self sendStartTLSRequest];
	
	// We do not mark the stream as secure yet.
	// We're waiting to receive the <proceed/> response from the
	// server before we actually start the TLS handshake.
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method checks the stream features of the connected server to determine if in-band registartion is supported.
 * If we are not connected to a server, this method simply returns NO.
**/
- (BOOL)supportsInBandRegistration
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	//stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		NSXMLElement *reg = [features elementForName:@"register" xmlns:@"http://jabber.org/features/iq-register"];
		
		return (reg != nil);
	}
	return NO;
}

/**
 * This method attempts to register a new user on the server using the given username and password.
 * The result of this action will be returned via the delegate methods.
 * 
 * If the XMPPStream is not connected, or the server doesn't support in-band registration, this method does nothing.
**/
- (BOOL)registerWithPassword:(NSString *)password error:(NSError **)errPtr
{
	if (state != STATE_CONNECTED)
	{
		if (errPtr)
		{
			NSString *errMsg = @"Please wait until the stream is connected.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidState userInfo:info];
		}
		return NO;
	}
	
	if (myJID == nil)
	{
		if (errPtr)
		{
			NSString *errMsg = @"You must set myJID before calling registerWithPassword:error:.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidProperty userInfo:info];
		}
		return NO;
	}
	
	if (![self supportsInBandRegistration])
	{
		if (errPtr)
		{
			NSString *errMsg = @"The server does not support in band registration.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamUnsupportedAction userInfo:info];
		}
		return NO;
	}
	
	NSString *username = [myJID user];
	
	NSXMLElement *queryElement = [NSXMLElement elementWithName:@"query" xmlns:@"jabber:iq:register"];
	[queryElement addChild:[NSXMLElement elementWithName:@"username" stringValue:username]];
	[queryElement addChild:[NSXMLElement elementWithName:@"password" stringValue:password]];
	
	NSXMLElement *iqElement = [NSXMLElement elementWithName:@"iq"];
	[iqElement addAttributeWithName:@"type" stringValue:@"set"];
	[iqElement addChild:queryElement];
	
    [transport sendStanza:iqElement];
	
	// Update state
	state = STATE_REGISTERING;
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Authentication
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method checks the stream features of the connected server to determine if SASL Anonymous Authentication (XEP-0175)
 * is supported. If we are not connected to a server, this method simply returns NO.
 **/
- (BOOL)supportsAnonymousAuthentication
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	// stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		NSXMLElement *mech = [features elementForName:@"mechanisms" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
		
		NSArray *mechanisms = [mech elementsForName:@"mechanism"];
		
		for (NSXMLElement *mechanism in mechanisms)
		{
			if ([[mechanism stringValue] isEqualToString:@"ANONYMOUS"])
			{
				return YES;
			}
		}
	}
	return NO;
}

/**
 * This method checks the stream features of the connected server to determine if plain authentication is supported.
 * If we are not connected to a server, this method simply returns NO.
**/
- (BOOL)supportsPlainAuthentication
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	//stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		NSXMLElement *mech = [features elementForName:@"mechanisms" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
		
		NSArray *mechanisms = [mech elementsForName:@"mechanism"];
		
		for (NSXMLElement *mechanism in mechanisms)
		{
			if ([[mechanism stringValue] isEqualToString:@"PLAIN"])
			{
				return YES;
			}
		}
	}
	return NO;
}

/**
 * This method checks the stream features of the connected server to determine if digest authentication is supported.
 * If we are not connected to a server, this method simply returns NO.
 * 
 * This is the preferred authentication technique, and will be used if the server supports it.
**/
- (BOOL)supportsDigestMD5Authentication
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	// stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		NSXMLElement *mech = [features elementForName:@"mechanisms" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
		
		NSArray *mechanisms = [mech elementsForName:@"mechanism"];
		
		for (NSXMLElement *mechanism in mechanisms)
		{
			if ([[mechanism stringValue] isEqualToString:@"DIGEST-MD5"])
			{
				return YES;
			}
		}
	}
	return NO;
}

/**
 * This method only applies to servers that don't support XMPP version 1.0, as defined in RFC 3920.
 * With these servers, we attempt to discover supported authentication modes via the jabber:iq:auth namespace.
**/
- (BOOL)supportsDeprecatedPlainAuthentication
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	// stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		// Search for an iq element within the rootElement.
		// Recall that some servers might stupidly add a "jabber:client" namespace which might cause problems
		// if we simply used the elementForName method.
		
		NSXMLElement *iq = nil;
		
		NSUInteger i, count = [rootElement childCount];
		for (i = 0; i < count; i++)
		{
			NSXMLNode *childNode = [rootElement childAtIndex:i];
			
			if ([childNode kind] == NSXMLElementKind)
			{
				if ([[childNode name] isEqualToString:@"iq"])
				{
					iq = (NSXMLElement *)childNode;
				}
			}
		}
		
		NSXMLElement *query = [iq elementForName:@"query" xmlns:@"jabber:iq:auth"];
		NSXMLElement *plain = [query elementForName:@"password"];
		
		return (plain != nil);
	}
	return NO;
}

/**
 * This method only applies to servers that don't support XMPP version 1.0, as defined in RFC 3920.
 * With these servers, we attempt to discover supported authentication modes via the jabber:iq:auth namespace.
**/
- (BOOL)supportsDeprecatedDigestAuthentication
{
	// The root element can be properly queried for authentication mechanisms anytime after the
	// stream:features are received, and TLS has been setup (if required)
	if (state > STATE_STARTTLS)
	{
		// Search for an iq element within the rootElement.
		// Recall that some servers might stupidly add a "jabber:client" namespace which might cause problems
		// if we simply used the elementForName method.
		
		NSXMLElement *iq = nil;
		
		NSUInteger i, count = [rootElement childCount];
		for (i = 0; i < count; i++)
		{
			NSXMLNode *childNode = [rootElement childAtIndex:i];
			
			if ([childNode kind] == NSXMLElementKind)
			{
				if ([[childNode name] isEqualToString:@"iq"])
				{
					iq = (NSXMLElement *)childNode;
				}
			}
		}
		
		NSXMLElement *query = [iq elementForName:@"query" xmlns:@"jabber:iq:auth"];
		NSXMLElement *digest = [query elementForName:@"digest"];
		
		return (digest != nil);
	}
	return NO;
}

/**
 * This method attempts to sign-in to the server using the configured myJID and given password.
 * If this method immediately fails
**/
- (BOOL)authenticateWithPassword:(NSString *)password error:(NSError **)errPtr
{
	if (state != STATE_CONNECTED)
	{
		if (errPtr)
		{
			NSString *errMsg = @"Please wait until the stream is connected.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidState userInfo:info];
		}
		return NO;
	}
	
	if (myJID == nil)
	{
		if (errPtr)
		{
			NSString *errMsg = @"You must set myJID before calling authenticateWithPassword:error:.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidProperty userInfo:info];
		}
		return NO;
	}
	
	if ([self supportsDigestMD5Authentication])
	{
		NSString *auth = @"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='DIGEST-MD5'/>";
        [transport sendStanzaWithString:auth];
		
		// Save authentication information
		[tempPassword release];
		tempPassword = [password copy];
		
		// Update state
		state = STATE_AUTH_1;
	}
	else if ([self supportsPlainAuthentication])
	{
		// From RFC 4616 - PLAIN SASL Mechanism:
		// [authzid] UTF8NUL authcid UTF8NUL passwd
		// 
		// authzid: authorization identity
		// authcid: authentication identity (username)
		// passwd : password for authcid
		
		NSString *username = [myJID user];
		
		NSString *payload = [NSString stringWithFormat:@"%C%@%C%@", 0, username, 0, password];
		NSString *base64 = [[payload dataUsingEncoding:NSUTF8StringEncoding] base64Encoded];
		
		NSXMLElement *auth = [NSXMLElement elementWithName:@"auth" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
		[auth addAttributeWithName:@"mechanism" stringValue:@"PLAIN"];
		[auth setStringValue:base64];
		
        [transport sendStanza:auth];
		
		// Update state
		state = STATE_AUTH_1;
	}
	else
	{
		// The server does not appear to support SASL authentication (at least any type we can use)
		// So we'll revert back to the old fashioned jabber:iq:auth mechanism
		
		NSString *username = [myJID user];
		NSString *resource = [myJID resource];
		
		if ([resource length] == 0)
		{
			// If resource is nil or empty, we need to auto-create one
			
			resource = [self generateUUID];
		}
		
		NSXMLElement *queryElement = [NSXMLElement elementWithName:@"query" xmlns:@"jabber:iq:auth"];
		[queryElement addChild:[NSXMLElement elementWithName:@"username" stringValue:username]];
		[queryElement addChild:[NSXMLElement elementWithName:@"resource" stringValue:resource]];
		
		if ([self supportsDeprecatedDigestAuthentication])
		{
			NSString *rootID = [[[self rootElement] attributeForName:@"id"] stringValue];
			NSString *digestStr = [NSString stringWithFormat:@"%@%@", rootID, password];
			NSData *digestData = [digestStr dataUsingEncoding:NSUTF8StringEncoding];
			
			NSString *digest = [[digestData sha1Digest] hexStringValue];
			
			[queryElement addChild:[NSXMLElement elementWithName:@"digest" stringValue:digest]];
		}
		else
		{
			[queryElement addChild:[NSXMLElement elementWithName:@"password" stringValue:password]];
		}
		
		NSXMLElement *iqElement = [NSXMLElement elementWithName:@"iq"];
		[iqElement addAttributeWithName:@"type" stringValue:@"set"];
		[iqElement addChild:queryElement];
		
        [transport sendStanza:iqElement];

		// Update state
		state = STATE_AUTH_1;
	}
	
	return YES;
}

/**
 * This method attempts to sign-in to the using SASL Anonymous Authentication (XEP-0175)
 **/
- (BOOL)authenticateAnonymously:(NSError **)errPtr
{
	if (state != STATE_CONNECTED)
	{
		if (errPtr)
		{
			NSString *errMsg = @"Please wait until the stream is connected.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamInvalidState userInfo:info];
		}
		return NO;
	}
	
	if (![self supportsAnonymousAuthentication])
	{
		if (errPtr)
		{
			NSString *errMsg = @"The server does not support anonymous authentication.";
			NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
			*errPtr = [NSError errorWithDomain:XMPPStreamErrorDomain code:XMPPStreamUnsupportedAction userInfo:info];
			
		}
		return NO;
	}
	
	NSXMLElement *auth = [NSXMLElement elementWithName:@"auth" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
	[auth addAttributeWithName:@"mechanism" stringValue:@"ANONYMOUS"];
	
    [transport sendStanza:auth];
	
	// Update state
	state = STATE_AUTH_3;
	
	return YES;
}

- (BOOL)isAuthenticated
{
	return (flags & kIsAuthenticated) ? YES : NO;
}
- (void)setIsAuthenticated:(BOOL)flag
{
	if(flag)
		flags |= kIsAuthenticated;
	else
		flags &= ~kIsAuthenticated;
}

/**
 * Custom Authentication.
**/
- (BOOL)startCustomAuthenticationWithTarget:(id)target authSelector:(SEL)authSelector handleAuthSelector:(SEL)handleAuthSelector
{
	if (state != STATE_CONNECTED)
	{
		return NO;
	}
	
	state = STATE_CUSTOM_AUTH;
	customAuthTarget = [target retain];
	customAuthSelector = authSelector;
	customHandleAuthSelector = handleAuthSelector;
	
	[target performSelector:authSelector];
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method will return the root element of the document.
 * This element contains the opening <stream:stream/> and <stream:features/> tags received from the server
 * when the XML stream was opened.
 * 
 * Note: The rootElement is empty, and does not contain all the XML elements the stream has received during it's
 * connection.  This is done for performance reasons and for the obvious benefit of being more memory efficient.
**/
- (NSXMLElement *)rootElement
{
	return rootElement;
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

/**
 * Private method.
 * Presencts a common method for the various public sendElement methods.
**/
- (void)sendElement:(NSXMLElement *)element withTag:(long)tag
{
	if ([element isKindOfClass:[XMPPIQ class]])
	{
		[multicastDelegate xmppStream:self willSendIQ:(XMPPIQ *)element];
	}
	else if ([element isKindOfClass:[XMPPMessage class]])
	{
		[multicastDelegate xmppStream:self willSendMessage:(XMPPMessage *)element];
	}
	else if ([element isKindOfClass:[XMPPPresence class]])
	{
		[multicastDelegate xmppStream:self willSendPresence:(XMPPPresence *)element];
	}
	else
	{
		NSString *elementName = [element name];
		
		if ([elementName isEqualToString:@"iq"])
		{
			[multicastDelegate xmppStream:self willSendIQ:[XMPPIQ iqFromElement:element]];
		}
		else if ([elementName isEqualToString:@"message"])
		{
			[multicastDelegate xmppStream:self willSendMessage:[XMPPMessage messageFromElement:element]];
		}
		else if ([elementName isEqualToString:@"presence"])
		{
			[multicastDelegate xmppStream:self willSendPresence:[XMPPPresence presenceFromElement:element]];
		}
	}
	
    [transport sendStanza:element];
	
	if ([element isKindOfClass:[XMPPIQ class]])
	{
		[multicastDelegate xmppStream:self didSendIQ:(XMPPIQ *)element];
	}
	else if ([element isKindOfClass:[XMPPMessage class]])
	{
		[multicastDelegate xmppStream:self didSendMessage:(XMPPMessage *)element];
	}
	else if ([element isKindOfClass:[XMPPPresence class]])
	{
		// Update myPresence if this is a normal presence element.
		// In other words, ignore presence subscription stuff, MUC room stuff, etc.
		
		XMPPPresence *presence = (XMPPPresence *)element;
		
		// We use the built-in [presence type] which guarantees lowercase strings,
		// and will return @"available" if there was no set type (as available is implicit).
		
		NSString *type = [presence type];
		if ([type isEqualToString:@"available"] || [type isEqualToString:@"unavailable"])
		{
			if ([presence toStr] == nil)
			{
				[myPresence release];
				myPresence = [presence retain];
			}
		}
		
		[multicastDelegate xmppStream:self didSendPresence:(XMPPPresence *)element];
	}
}

/**
 * This methods handles sending an XML fragment.
 * If the XMPPStream is not connected, this method does nothing.
**/
- (void)sendElement:(NSXMLElement *)element
{
	if (state == STATE_CONNECTED || state == STATE_CUSTOM_AUTH)
	{
		[self sendElement:element withTag:0];
	}
}

/**
 * This method handles sending an XML fragment.
 * If the XMPPStream is not connected, this method does nothing.
 * 
 * After the element has been successfully sent,
 * the xmppStream:didSendElementWithTag: delegate method is called.
**/
- (void)sendElement:(NSXMLElement *)element andNotifyMe:(UInt16)tag
{
	if (state == STATE_CONNECTED)
	{
		[self sendElement:element withTag:tag];
	}
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Stream Negotiation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)restartStream
{
    [transport restartStream];
}

/**
 * This method is called anytime we receive the server's stream features.
 * This method looks at the stream features, and handles any requirements so communication can continue.
**/
- (void)handleStreamFeatures
{
	// Extract the stream features
	NSXMLElement *features = [rootElement elementForName:@"stream:features"];
	
	// Check to see if TLS is required
	// Don't forget about that NSXMLElement bug you reported to apple (xmlns is required or element won't be found)
	NSXMLElement *f_starttls = [features elementForName:@"starttls" xmlns:@"urn:ietf:params:xml:ns:xmpp-tls"];
	
	if (f_starttls)
	{
		if ([f_starttls elementForName:@"required"])
		{
			// TLS is required for this connection
			
			// Update state
			state = STATE_STARTTLS;
			
			// Send the startTLS XML request
			[self sendStartTLSRequest];
			
			// We do not mark the stream as secure yet.
			// We're waiting to receive the <proceed/> response from the
			// server before we actually start the TLS handshake.
			
			// We're already listening for the response...
			return;
		}
	}
	
	// Check to see if resource binding is required
	// Don't forget about that NSXMLElement bug you reported to apple (xmlns is required or element won't be found)
	NSXMLElement *f_bind = [features elementForName:@"bind" xmlns:@"urn:ietf:params:xml:ns:xmpp-bind"];
	
	if ([self isAuthenticated] && f_bind)
	{
		// Binding is required for this connection
		state = STATE_BINDING;
		
		NSString *requestedResource = [myJID resource];
		
		if ([requestedResource length] > 0)
		{
			// Ask the server to bind the user specified resource
			
			NSXMLElement *resource = [NSXMLElement elementWithName:@"resource"];
			[resource setStringValue:requestedResource];
			
			NSXMLElement *bind = [NSXMLElement elementWithName:@"bind" xmlns:@"urn:ietf:params:xml:ns:xmpp-bind"];
			[bind addChild:resource];
			
			NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
			[iq addAttributeWithName:@"type" stringValue:@"set"];
			[iq addChild:bind];
			
            [transport sendStanza:iq];
		}
		else
		{
			// The user didn't specify a resource, so we ask the server to bind one for us
			
			NSXMLElement *bind = [NSXMLElement elementWithName:@"bind" xmlns:@"urn:ietf:params:xml:ns:xmpp-bind"];
			
			NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
			[iq addAttributeWithName:@"type" stringValue:@"set"];
			[iq addChild:bind];
			
            [transport sendStanza:iq];
		}
		
		// We're already listening for the response...
		return;
	}
	
	// It looks like all has gone well, and the connection should be ready to use now
	state = STATE_CONNECTED;
	
	if (![self isAuthenticated])
	{
		// Notify delegates
		[multicastDelegate xmppStreamDidConnect:self];
	}
}

- (void)handleStartTLSResponse:(NSXMLElement *)response
{
	// We're expecting a proceed response
	// If we get anything else we can safely assume it's the equivalent of a failure response
	if(![[response name] isEqualToString:@"proceed"])
	{
		// We can close our TCP connection now
		[self disconnect];
		
		// The onSocketDidDisconnect: method will handle everything else
		return;
	}
	
	// Start TLS negotiation
	[transport secure];
	
	// Make a note of the switch to TLS
	[self setIsSecure:YES];
}

/**
 * After the registerUser:withPassword: method is invoked, a registration message is sent to the server.
 * We're waiting for the result from this registration request.
**/
- (void)handleRegistration:(NSXMLElement *)response
{
	if([[[response attributeForName:@"type"] stringValue] isEqualToString:@"error"])
	{
		// Revert back to connected state (from authenticating state)
		state = STATE_CONNECTED;
		
		[multicastDelegate xmppStream:self didNotRegister:response];
	}
	else
	{
		// Revert back to connected state (from authenticating state)
		state = STATE_CONNECTED;
		
		[multicastDelegate xmppStreamDidRegister:self];
	}
}

/**
 * After the authenticateUser:withPassword:resource method is invoked, a authentication message is sent to the server.
 * If the server supports digest-md5 sasl authentication, it is used.  Otherwise plain sasl authentication is used,
 * assuming the server supports it.
 * 
 * Now if digest-md5 was used, we sent a challenge request, and we're waiting for a challenge response.
 * If plain sasl was used, we sent our authentication information, and we're waiting for a success response.
**/
- (void)handleAuth1:(NSXMLElement *)response
{
	if([self supportsDigestMD5Authentication])
	{
		// We're expecting a challenge response
		// If we get anything else we can safely assume it's the equivalent of a failure response
		if(![[response name] isEqualToString:@"challenge"])
		{
			// Revert back to connected state (from authenticating state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStream:self didNotAuthenticate:response];
		}
		else
		{
			// Create authentication object from the given challenge
			// We'll release this object at the end of this else block
			XMPPDigestAuthentication *auth = [[XMPPDigestAuthentication alloc] initWithChallenge:response];
			
			NSString *virtualHostName = [myJID domain];
			
			// Sometimes the realm isn't specified
			// In this case I believe the realm is implied as the virtual host name
            // Note: earlier, in case the virtual host name was not set, the server host name was used.
            // However with the introduction of BOSH, we can't always know the server host name,
            // so we rely only on virtual hostnames for auth realm and digest URI.
			if (![auth realm])
			{
                [auth setRealm:virtualHostName];
			}
			
			// Set digest-uri
            [auth setDigestURI:[NSString stringWithFormat:@"xmpp/%@", virtualHostName]];
			
			// Set username and password
			[auth setUsername:[myJID user] password:tempPassword];
			
			// Create and send challenge response element
			NSXMLElement *cr = [NSXMLElement elementWithName:@"response" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
			[cr setStringValue:[auth base64EncodedFullResponse]];
			
            [transport sendStanza:cr];
            
			// Release unneeded resources
			[auth release];
			[tempPassword release]; tempPassword = nil;
			
			// Update state
			state = STATE_AUTH_2;
		}
	}
	else if([self supportsPlainAuthentication])
	{
		// We're expecting a success response
		// If we get anything else we can safely assume it's the equivalent of a failure response
		if(![[response name] isEqualToString:@"success"])
		{
			// Revert back to connected state (from authenticating state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStream:self didNotAuthenticate:response];
		}
		else
		{
			// We are successfully authenticated (via sasl:plain)
			[self setIsAuthenticated:YES];
			state = STATE_NEGOTIATING;
			
			// Now we start our negotiation over again...
			[self restartStream];
		}
	}
	else
	{
		// We used the old fashioned jabber:iq:auth mechanism
		
		if([[[response attributeForName:@"type"] stringValue] isEqualToString:@"error"])
		{
			// Revert back to connected state (from authenticating state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStream:self didNotAuthenticate:response];
		}
		else
		{
			// We are successfully authenticated (via non-sasl:digest)
			// And we've binded our resource as well
			[self setIsAuthenticated:YES];
			
			// Revert back to connected state (from authenticating state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStreamDidAuthenticate:self];
		}
	}
}

/**
 * This method handles the result of our challenge response we sent in handleAuth1 using digest-md5 sasl.
**/
- (void)handleAuth2:(NSXMLElement *)response
{
	if([[response name] isEqualToString:@"challenge"])
	{
		XMPPDigestAuthentication *auth = [[[XMPPDigestAuthentication alloc] initWithChallenge:response] autorelease];
		
		if(![auth rspauth])
		{
			// We're getting another challenge???
			// I'm not sure what this could possibly be, so for now I'll assume it's a failure
			
			// Revert back to connected state (from authenticating state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStream:self didNotAuthenticate:response];
		}
		else
		{
			// We received another challenge, but it's really just an rspauth
			// This is supposed to be included in the success element (according to the updated RFC)
			// but many implementations incorrectly send it inside a second challenge request.
			
			// Create and send empty challenge response element
			NSXMLElement *cr = [NSXMLElement elementWithName:@"response" xmlns:@"urn:ietf:params:xml:ns:xmpp-sasl"];
			
            [transport sendStanza:cr];
			
			// The state remains in STATE_AUTH_2
		}
	}
	else if([[response name] isEqualToString:@"success"])
	{
		// We are successfully authenticated (via sasl:digest-md5)
		[self setIsAuthenticated:YES];
		state = STATE_NEGOTIATING;
		// Now we start our negotiation over again...
		[self restartStream];
	}
	else
	{
		// We received some kind of <failure/> element
		
		// Revert back to connected state (from authenticating state)
		state = STATE_CONNECTED;
		[multicastDelegate xmppStream:self didNotAuthenticate:response];
	}
}

/**
 * This method handles the result of our SASL Anonymous Authentication challenge
**/
- (void)handleAuth3:(NSXMLElement *)response
{
	// We're expecting a success response
	// If we get anything else we can safely assume it's the equivalent of a failure response
	if(![[response name] isEqualToString:@"success"])
	{
		// Revert back to connected state (from authenticating state)
		state = STATE_CONNECTED;
		
		[multicastDelegate xmppStream:self didNotAuthenticate:response];
	}
	else
	{
		// We are successfully authenticated (via sasl:x-facebook-platform or sasl:plain)
		[self setIsAuthenticated:YES];
		
		// Now we start our negotiation over again...
		[self restartStream];
	}
}

- (void)handleBinding:(NSXMLElement *)response
{
	NSXMLElement *r_bind = [response elementForName:@"bind" xmlns:@"urn:ietf:params:xml:ns:xmpp-bind"];
	NSXMLElement *r_jid = [r_bind elementForName:@"jid"];
	
	if(r_jid)
	{
		// We're properly binded to a resource now
		// Extract and save our resource (it may not be what we originally requested)
		NSString *fullJIDStr = [r_jid stringValue];
		
		[myJID release];
		myJID = [[XMPPJID jidWithString:fullJIDStr] retain];
		
		// And we may now have to do one last thing before we're ready - start an IM session
		NSXMLElement *features = [rootElement elementForName:@"stream:features"];
		
		// Check to see if a session is required
		// Don't forget about that NSXMLElement bug you reported to apple (xmlns is required or element won't be found)
		NSXMLElement *f_session = [features elementForName:@"session" xmlns:@"urn:ietf:params:xml:ns:xmpp-session"];
		
		if(f_session)
		{
			NSXMLElement *session = [NSXMLElement elementWithName:@"session"];
			[session setXmlns:@"urn:ietf:params:xml:ns:xmpp-session"];
			
			NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
			[iq addAttributeWithName:@"type" stringValue:@"set"];
			[iq addChild:session];
			
            [transport sendStanza:iq];
			// Update state
			state = STATE_START_SESSION;
		}
		else
		{
			// Revert back to connected state (from binding state)
			state = STATE_CONNECTED;
			
			[multicastDelegate xmppStreamDidAuthenticate:self];
		}
	}
	else
	{
		// It appears the server didn't allow our resource choice
		// We'll simply let the server choose then
		
		NSXMLElement *bind = [NSXMLElement elementWithName:@"bind" xmlns:@"urn:ietf:params:xml:ns:xmpp-bind"];
		
		NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
		[iq addAttributeWithName:@"type" stringValue:@"set"];
		[iq addChild:bind];
		
		[transport sendStanza:iq];
		// The state remains in STATE_BINDING
	}
}

- (void)handleStartSessionResponse:(NSXMLElement *)response
{
	if([[[response attributeForName:@"type"] stringValue] isEqualToString:@"result"])
	{
		// Revert back to connected state (from start session state)
		state = STATE_CONNECTED;
		
		[multicastDelegate xmppStreamDidAuthenticate:self];
	}
  
  //Commenting out this code since pappu doesn't honour rfc right now
  //should be changed once pappu starts doing the correct thing.
  /*
	else
	{
		// Revert back to connected state (from start session state)
		state = STATE_CONNECTED;
		
		[multicastDelegate xmppStream:self didNotAuthenticate:response];
	}
   */
}

/**
 * Handling of custom authentication responses.
**/
- (void)didFinishCustomAuthentication {
	// We are successfully authenticated
	[self setIsAuthenticated:YES];
	state = STATE_NEGOTIATING;
	
	// Now we start our negotiation over again...
	[self restartStream];
	[customAuthTarget release];
}

- (void)didFailCustomAuthentication:(NSXMLElement *)response {
	// Revert back to connected state (from authenticating state)
	state = STATE_CONNECTED;
	
	[multicastDelegate xmppStream:self didNotAuthenticate:response];
	[customAuthTarget release];
}

//////////////////////////////////////
#pragma mark XMPPTransport Delegate
//////////////////////////////////////

- (void)transportDidConnect:(id<XMPPTransportProtocol>)sender
{	
	// At this point we've sent our XML stream header, and we've received the response XML stream header.
	// We save the root element of our stream for future reference.
	// Digest Access authentication requires us to know the ID attribute from the <stream:stream/> element.
	
	[rootElement release];
	rootElement = [[self newRootElement] retain];
    if ([self isP2P] && [self isP2PRecipient])
    {
        self.remoteJID = [transport remoteJID];
        NSXMLElement *streamFeatures = [NSXMLElement elementWithName:@"stream:features"];
        [transport sendStanza:streamFeatures];
        state = STATE_CONNECTED;
        return;
    }
	
    // Check for RFC compliance
    if([transport serverXmppStreamVersionNumber] >= 1.0)
    {
        // Update state - we're now onto stream negotiations
        state = STATE_NEGOTIATING;
        
        // Note: We're waiting for the <stream:features> now
    }
    else
    {
        // The server isn't RFC comliant, and won't be sending any stream features.
        
        // We would still like to know what authentication features it supports though,
        // so we'll use the jabber:iq:auth namespace, which was used prior to the RFC spec.
        
        // Update state - we're onto psuedo negotiation
        state = STATE_NEGOTIATING;
        
        NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"jabber:iq:auth"];
        
        NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
        [iq addAttributeWithName:@"type" stringValue:@"get"];
        [iq addChild:query];
        
        [transport sendStanza:iq];
        
        // Now wait for the response IQ
    }
}

- (void)transport:(id<XMPPTransportProtocol>)sender didReceiveStanza:(NSXMLElement *)element
{
	NSString *elementName = [element name];

	if([elementName isEqualToString:@"stream:error"] || [elementName isEqualToString:@"error"])
	{
		[multicastDelegate xmppStream:self didReceiveError:element];
		return;
	}

	if(state == STATE_NEGOTIATING)
	{
		// We've just read in the stream features
		// We consider this part of the root element, so we'll add it (replacing any previously sent features)
		NSXMLElement *newElement = [element copy];
		[rootElement setChildren:[NSArray arrayWithObject:newElement]];
		[newElement release];
		
		// Call a method to handle any requirements set forth in the features
		[self handleStreamFeatures];
	}
	else if(state == STATE_STARTTLS)
	{
		// The response from our starttls message
		[self handleStartTLSResponse:element];
	}
	else if(state == STATE_REGISTERING)
	{
		// The iq response from our registration request
		[self handleRegistration:element];
	}
	else if (state == STATE_CUSTOM_AUTH)
	{
		//The customAuthTarget must respond to this selector.
		[customAuthTarget performSelector:customHandleAuthSelector withObject:element];
	}
	else if(state == STATE_AUTH_1)
	{
		// The challenge response from our auth message
		[self handleAuth1:element];
	}
	else if(state == STATE_AUTH_2)
	{
		// The response from our challenge response
		[self handleAuth2:element];
	}
	else if(state == STATE_AUTH_3)
	{
		// The response from our x-facebook-platform or authenticateAnonymously challenge
		[self handleAuth3:element];
	}
	else if(state == STATE_BINDING)
	{
		// The response from our binding request
		[self handleBinding:element];
	}
	else if(state == STATE_START_SESSION)
	{
		// The response from our start session request
		[self handleStartSessionResponse:element];
	}
	else
	{
		if([elementName isEqualToString:@"iq"])
		{
			XMPPIQ *iq = [XMPPIQ iqFromElement:element];
			
			BOOL responded = NO;
			
			MulticastDelegateEnumerator *delegateEnumerator = [multicastDelegate delegateEnumerator];
			id delegate;
			SEL selector = @selector(xmppStream:didReceiveIQ:);
			
			while((delegate = [delegateEnumerator nextDelegateForSelector:selector]))
			{
				BOOL delegateDidRespond = [delegate xmppStream:self didReceiveIQ:iq];
				
				responded = responded || delegateDidRespond;
			}
			
			// An entity that receives an IQ request of type "get" or "set" MUST reply
			// with an IQ response of type "result" or "error".
			// 
			// The response MUST preserve the 'id' attribute of the request.
			
			if (!responded && [iq requiresResponse])
			{
				// Return error message:
				// 
				// <iq to="jid" type="error" id="id">
				//   <query xmlns="ns"/>
				//   <error type="cancel" code="501">
				//     <feature-not-implemented xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>
				//   </error>
				// </iq>
				
				NSXMLElement *reason = [NSXMLElement elementWithName:@"feature-not-implemented"
				                                               xmlns:@"urn:ietf:params:xml:ns:xmpp-stanzas"];
				
				NSXMLElement *error = [NSXMLElement elementWithName:@"error"];
				[error addAttributeWithName:@"type" stringValue:@"cancel"];
				[error addAttributeWithName:@"code" stringValue:@"501"];
				[error addChild:reason];
				
				XMPPIQ *iqResponse = [XMPPIQ iqWithType:@"error" to:[iq from] elementID:[iq elementID] child:error];
				
				NSXMLElement *iqChild = [iq childElement];
				if (iqChild)
				{
					NSXMLNode *iqChildCopy = [iqChild copy];
					[iqResponse insertChild:iqChildCopy atIndex:0];
					[iqChildCopy release];
				}
				
				[self sendElement:iqResponse];
			}
		}
		else if([elementName isEqualToString:@"message"])
		{
			[multicastDelegate xmppStream:self didReceiveMessage:[XMPPMessage messageFromElement:element]];
		}
		else if([elementName isEqualToString:@"presence"])
		{
			[multicastDelegate xmppStream:self didReceivePresence:[XMPPPresence presenceFromElement:element]];
		}
		else if([self isP2P] &&
                ([elementName isEqualToString:@"stream:features"] || [elementName isEqualToString:@"features"]))
		{
			[multicastDelegate xmppStream:self didReceiveP2PFeatures:element];
		}
		else
		{
			[multicastDelegate xmppStream:self didReceiveError:element];
		}
	}
}

- (void)transportDidSecure:(id<XMPPTransportProtocol>)sender
{
    [multicastDelegate xmppStreamDidSecure:self];
    [self restartStream];
}

- (void)transportWillDisconnect:(id<XMPPTransportProtocol>)sender withError:(NSError *)err
{
    [multicastDelegate xmppStream:self didReceiveError:err];
}

- (void)transportDidDisconnect:(id<XMPPTransportProtocol>)sender
{
    state = STATE_DISCONNECTED;
    
    [rootElement release];
    rootElement = nil;
    
    [multicastDelegate xmppStreamDidDisconnect:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSString *)generateUUID
{
	NSString *result = nil;
	
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	if (uuid)
	{
		result = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
		CFRelease(uuid);
	}
	
	return [result autorelease];
}

- (NSString *)generateUUID
{
	return [[self class] generateUUID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Module Plug-In System
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)registerModule:(XMPPModule *)module
{
	if (module == nil) return;
	
	// Register module
	
	[registeredModules addDelegate:module];
	
	// Add auto delegates (if there are any)
	
	NSString *className = NSStringFromClass([module class]);
	id delegates = [autoDelegateDict objectForKey:className];
	
	MulticastDelegateEnumerator *delegatesEnumerator = [delegates delegateEnumerator];
	id delegate;
	
	while ((delegate = [delegatesEnumerator nextDelegate]))
	{
		[module addDelegate:delegate];
	}
	
	// Notify our own delegate(s)
	
	[multicastDelegate xmppStream:self didRegisterModule:module];
}

- (void)unregisterModule:(XMPPModule *)module
{
	if (module == nil) return;
	
	// Notify our own delegate(s)
	
	[multicastDelegate xmppStream:self willUnregisterModule:module];
	
	// Auto remove delegates (if there are any)
	
	NSString *className = NSStringFromClass([module class]);
	id delegates = [autoDelegateDict objectForKey:className];
	
	MulticastDelegateEnumerator *delegatesEnumerator = [delegates delegateEnumerator];
	id delegate;
	
	while ((delegate = [delegatesEnumerator nextDelegate]))
	{
		[module removeDelegate:delegate];
	}
	
	// Unregister modules
	
	[registeredModules removeDelegate:module];
}

- (void)autoAddDelegate:(id)delegate toModulesOfClass:(Class)aClass
{
	if (aClass == nil) return;
	
	NSString *className = NSStringFromClass(aClass);
	
	// Add the delegate to all currently registered modules of the given class.
	
	MulticastDelegateEnumerator *registeredModulesEnumerator = [registeredModules delegateEnumerator];
	XMPPModule *module;
	
	while ((module = [registeredModulesEnumerator nextDelegateOfClass:aClass]))
	{
		[module addDelegate:delegate];
	}
	
	// Add the delegate to list of auto delegates for the given class,
	// so that it will be added as a delegate to future registered modules of the given class.
	
	id delegates = [autoDelegateDict objectForKey:className];
	
	if (delegates == nil)
	{
		delegates = [[[MulticastDelegate alloc] init] autorelease];
		
		[autoDelegateDict setObject:delegates forKey:className];
	}
	
	[delegates addDelegate:delegate];
}

- (void)removeAutoDelegate:(id)delegate fromModulesOfClass:(Class)aClass
{
	if (aClass == nil)
	{
		// Remove the delegate from all currently registered modules of any class.
		
		[registeredModules removeDelegate:delegate];
		
		// Remove the delegate from list of auto delegates for all classes,
		// so that it will not be auto added as a delegate to future registered modules.
		
		NSEnumerator *delegatesEnumerator = [autoDelegateDict objectEnumerator];
		id delegates;
		
		while ((delegates = [delegatesEnumerator nextObject]))
		{
			[delegates removeDelegate:self];
		}
	}
	else
	{
		NSString *className = NSStringFromClass(aClass);
		
		// Remove the delegate from all currently registered modules of the given class.
		
		MulticastDelegateEnumerator *registeredModulesEnumerator = [registeredModules delegateEnumerator];
		XMPPModule *module;
		
		while ((module = [registeredModulesEnumerator nextDelegateOfClass:aClass]))
		{
			[module removeDelegate:delegate];
		}
		
		// Remove the delegate from list of auto delegates for the given class,
		// so that it will not be added as a delegate to future registered modules of the given class.
		
		id delegates = [autoDelegateDict objectForKey:className];
		
		if (delegates != nil)
		{
			[delegates removeDelegate:delegate];
		}
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPDigestAuthentication

- (id)initWithChallenge:(NSXMLElement *)challenge
{
	if((self = [super init]))
	{
		// Convert the base 64 encoded data into a string
		NSData *base64Data = [[challenge stringValue] dataUsingEncoding:NSASCIIStringEncoding];
		NSData *decodedData = [base64Data base64Decoded];
		
		NSString *authStr = [[[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding] autorelease];
		
        DDLogInfo(@"decoded challenge: %@", authStr);
		
		// Extract all the key=value pairs, and put them in a dictionary for easy lookup
		NSMutableDictionary *auth = [NSMutableDictionary dictionaryWithCapacity:5];
		
		NSArray *components = [authStr componentsSeparatedByString:@","];
		
		int i;
		for(i = 0; i < [components count]; i++)
		{
			NSString *component = [components objectAtIndex:i];
			
			NSRange separator = [component rangeOfString:@"="];
			if(separator.location != NSNotFound)
			{
				NSMutableString *key = [[component substringToIndex:separator.location] mutableCopy];
				NSMutableString *value = [[component substringFromIndex:separator.location+1] mutableCopy];
				
				if(key) CFStringTrimWhitespace((CFMutableStringRef)key);
				if(value) CFStringTrimWhitespace((CFMutableStringRef)value);
				
				if([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] > 2)
				{
					// Strip quotes from value
					[value deleteCharactersInRange:NSMakeRange(0, 1)];
					[value deleteCharactersInRange:NSMakeRange([value length]-1, 1)];
				}
				
				[auth setObject:value forKey:key];
				
				[value release];
				[key release];
			}
		}
		
		// Extract and retain the elements we need
		rspauth = [[auth objectForKey:@"rspauth"] copy];
		realm = [[auth objectForKey:@"realm"] copy];
		nonce = [[auth objectForKey:@"nonce"] copy];
		qop = [[auth objectForKey:@"qop"] copy];
		
		// Generate cnonce
		cnonce = [[XMPPStream generateUUID] retain];
	}
	return self;
}

- (void)dealloc
{
	[rspauth release];
	[realm release];
	[nonce release];
	[qop release];
	[username release];
	[password release];
	[cnonce release];
	[nc release];
	[digestURI release];
	[super dealloc];
}

- (NSString *)rspauth
{
	return [[rspauth copy] autorelease];
}

- (NSString *)realm
{
	return [[realm copy] autorelease];
}

- (void)setRealm:(NSString *)newRealm
{
	if(![realm isEqual:newRealm])
	{
		[realm release];
		realm = [newRealm copy];
	}
}

- (void)setDigestURI:(NSString *)newDigestURI
{
	if(![digestURI isEqual:newDigestURI])
	{
		[digestURI release];
		digestURI = [newDigestURI copy];
	}
}

- (void)setUsername:(NSString *)newUsername password:(NSString *)newPassword
{
	if(![username isEqual:newUsername])
	{
		[username release];
		username = [newUsername copy];
	}
	
	if(![password isEqual:newPassword])
	{
		[password release];
		password = [newPassword copy];
	}
}

- (NSString *)response
{
	NSString *HA1str = [NSString stringWithFormat:@"%@:%@:%@", username, realm, password];
	NSString *HA2str = [NSString stringWithFormat:@"AUTHENTICATE:%@", digestURI];
	
	NSData *HA1dataA = [[HA1str dataUsingEncoding:NSUTF8StringEncoding] md5Digest];
	NSData *HA1dataB = [[NSString stringWithFormat:@":%@:%@", nonce, cnonce] dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableData *HA1data = [NSMutableData dataWithCapacity:([HA1dataA length] + [HA1dataB length])];
	[HA1data appendData:HA1dataA];
	[HA1data appendData:HA1dataB];
	
	NSString *HA1 = [[HA1data md5Digest] hexStringValue];
	
	NSString *HA2 = [[[HA2str dataUsingEncoding:NSUTF8StringEncoding] md5Digest] hexStringValue];
	
	NSString *responseStr = [NSString stringWithFormat:@"%@:%@:00000001:%@:auth:%@",
		HA1, nonce, cnonce, HA2];
	
	NSString *response = [[[responseStr dataUsingEncoding:NSUTF8StringEncoding] md5Digest] hexStringValue];
	
	return response;
}

- (NSString *)base64EncodedFullResponse
{
	NSMutableString *buffer = [NSMutableString stringWithCapacity:100];
	[buffer appendFormat:@"username=\"%@\",", username];
	[buffer appendFormat:@"realm=\"%@\",", realm];
	[buffer appendFormat:@"nonce=\"%@\",", nonce];
	[buffer appendFormat:@"cnonce=\"%@\",", cnonce];
	[buffer appendFormat:@"nc=00000001,"];
	[buffer appendFormat:@"qop=auth,"];
	[buffer appendFormat:@"digest-uri=\"%@\",", digestURI];
	[buffer appendFormat:@"response=%@,", [self response]];
	[buffer appendFormat:@"charset=utf-8"];
	
	DDLogInfo(@"decoded response: %@", buffer);
	
	NSData *utf8data = [buffer dataUsingEncoding:NSUTF8StringEncoding];
	
	return [utf8data base64Encoded];
}

@end
