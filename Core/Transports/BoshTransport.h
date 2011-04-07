//
//  BoshTransport.h
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPTransportProtocol.h"
#import "XMPPJID.h"
#import "MulticastDelegate.h"
#import "ASIHTTPRequest.h"

typedef enum {
    ATTR_TYPE = 0,
    NAMESPACE_TYPE = 1
} XMLNodeType;

/*
 host-unknown
 host-gone
 item-not-found
 policy-violation
 remote-connection-failed
 bad-request
 internal-server-error
 remote-stream-error
 undefined-condition
 */

typedef enum {
    HOST_UNKNOWN = 1,
    HOST_GONE = 2,
    ITEM_NOT_FOUND = 3,
    POLICY_VIOLATION = 4,
    REMOTE_CONNECTION_FAILED = 5,
    BAD_REQUEST = 6,
    INTERNAL_SERVER_ERROR = 7,
    REMOTE_STREAM_ERROR = 8,
    UNDEFINED_CONDITION = 9
} BoshTerminateConditions;

typedef enum {
    CONNECTED = 0,
    CONNECTING = 1,
    DISCONNECTING = 2,
    DISCONNECTED = 3,
    TERMINATED = 4
} BoshTransportState;

@protocol BoshWindowProtocol
- (void)broadcastStanzas:(NSXMLNode *)node;
@end

@interface RequestResponsePair : NSObject
@property(retain) NSXMLElement *request;
@property(retain) NSXMLElement *response;
- (id)initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response;
- (void)dealloc;
@end

@interface BoshWindowManager : NSObject {
	NSMutableDictionary *window;
	long long maxRidReceived;
	long long maxRidSent;
	id delegate;
}

@property long long windowSize;
@property(readonly) long long outstandingRequests;

- (void)sentRequest:(NSXMLElement *)request;
- (void)recievedResponse:(NSXMLElement *)response forRid:(long long)rid;
- (BOOL)canSendMoreRequests;
- (NSNumber *)maxRidReceived;
- (BOOL)canLetServerHoldRequests:(long long)hold;
- (NSXMLElement *)getRequestForRid:(long long)rid;
- (id)initWithDelegate:(id)del rid:(long long)rid;
- (void)dealloc;
@end

@interface BoshTransport : NSObject <XMPPTransportProtocol, BoshWindowProtocol > {
	NSString *boshVersion;

	NSString *content;
    NSString *STREAM_NS;
    NSString *BODY_NS;
    NSString *XMPP_NS;

    long long nextRidToSend;
	
	NSMutableArray *pendingXMPPStanzas;
	BoshWindowManager *boshWindowManager;
    BoshTransportState state;
    
    NSMutableSet *pendingHttpRequests;
	MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
    NSError *disconnectError_;
}

@property(retain) XMPPJID *myJID;
@property(retain) NSNumber *wait;
@property(retain) NSNumber *hold;
@property(copy) NSString *lang;
@property(copy) NSString *domain;
@property(readonly) NSNumber *inactivity;
@property(readonly) BOOL secure;
@property(readonly) NSNumber *requests;
@property(copy) NSString *authid;
@property(copy) NSString *sid;
@property(copy) NSString *url;
@property(readonly) NSError *disconnectError;

/* init Methods */
- (id)initWithUrl:(NSString *)url forDomain:(NSString *)host;
- (id)initWithUrl:(NSString *)url forDomain:(NSString *)host withDelegate:(id<XMPPTransportDelegate>)delegate;

- (void)dealloc;

/* ASI http methods - Delegate Methods */
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;

/* Protocol Methods */
- (BOOL)isConnected;
- (void)addDelegate:(id)delegate;
- (void)removeDelegate:(id)delegate;
- (XMPPJID *)myJID;
- (void)setMyJID:(XMPPJID *)jid;
- (BOOL)connect:(NSError **)errPtr;
- (void)disconnect;
- (void)restartStream;
- (float)serverXmppStreamVersionNumber;
- (BOOL)sendStanza:(NSXMLElement *)stanza;
- (BOOL)sendStanzaWithString:(NSString *)string;

/* Methods used internally */
- (BOOL)canConnect;
- (void)handleAttributesInResponse:(NSXMLElement *)parsedResponse;
- (NSString *)logRequestResponse:(NSData *)data;
- (void)createSessionResponseHandler:(NSXMLElement *)parsedResponse;
- (void)disconnectSessionResponseHandler:(ASIHTTPRequest *)request;
- (long long)generateRid;
- (NSArray *)convertToStrings:(NSArray *)array;
- (SEL)setterForProperty:(NSString *)property;
- (NSNumber *)numberFromString:(NSString *)stringNumber;
- (void)sendHTTPRequestWithBody:(NSXMLElement *)body;
- (void)broadcastStanzas:(NSXMLNode *)node;
- (void)trySendingStanzas;
- (void)makeBodyAndSendHTTPRequestWithPayload:(NSArray *)bodyPayload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
- (long long)getRidInRequest:(NSXMLElement *)body;
- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
- (NSArray *)createXMLNodeArrayFromDictionary:(NSDictionary *)dict ofType:(XMLNodeType)type;
- (NSXMLElement *)parseXMLData:(NSData *)xml;
- (NSXMLElement *)parseXMLString:(NSString *)xml;
- (void)sendRequestsToHold;
- (BOOL) createSession:(NSError **)error;
@end
