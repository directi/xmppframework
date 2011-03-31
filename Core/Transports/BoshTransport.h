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
- (void)recievedResponse:(NSXMLElement *)response;
- (BOOL)canSendMoreRequests;
- (BOOL)canLetServerHoldRequests:(long long)hold;
- (NSXMLElement *)getRequestForRid:(long long)rid;
- (id)initWithDelegate:(id)del rid:(long long)rid;
@end

@interface BoshTransport : NSObject <XMPPTransportProtocol, BoshWindowProtocol > {
	NSString *boshVersion;
	NSNumber *ack;

	NSString *content;
    NSString *STREAM_NS;
    NSString *BODY_NS;
    NSString *XMPP_NS;
        
    long long nextRidToSend;
	
	NSMutableArray *pendingXMPPStanzas;
	BoshWindowManager *boshWindowManager;
        
	MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
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

/* init Methods */
- (id)initWithUrl:(NSString *)url forDomain:(NSString *)host;
- (id)initWithUrl:(NSString *)url forDomain:(NSString *)host withDelegate:(id<XMPPTransportDelegate>)delegate;

/* ASI http methods - Delegate Methods */
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;

/* Protocol Methods */
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
- (void)sessionResponseHandler:(ASIHTTPRequest *)request;
- (long long)generateRid;
- (NSArray *)convertToStrings:(NSArray *)array;
- (SEL)setterForProperty:(NSString *)property;
- (NSNumber *)numberFromString:(NSString *)stringNumber;
- (void)sendHTTPRequestWithBody:(NSXMLElement *)body responseHandler:(SEL)responseHandler errorHandler:(SEL)errorHandler;
- (void)broadcastStanzas:(NSXMLNode *)node;
- (void)trySendingStanzas;
- (void)sendRequest:(NSArray *)bodyPayload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
- (long long)getRidInRequest:(NSXMLElement *)body;
- (NSXMLElement *)newBodyElementWithPayload:(NSArray *)payload attributes:(NSMutableDictionary *)attributes namespaces:(NSMutableDictionary *)namespaces;
- (NSArray *)createXMLNodeArrayFromDictionary:(NSDictionary *)dict ofType:(XMLNodeType)type;
- (NSXMLElement *)parseXMLData:(NSData *)xml;
- (NSXMLElement *)parseXMLString:(NSString *)xml;
- (void)sendRequestsToHold;
- (BOOL) startSession:(NSError **)error;
@end
