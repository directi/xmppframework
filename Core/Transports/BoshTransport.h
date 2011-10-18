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

#define BoshTerminateConditionDomain @"BoshTerminateCondition"

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
    TERMINATING = 4
} BoshTransportState;

@interface RequestResponsePair : NSObject <NSCoding> 
@property (nonatomic, retain) NSXMLElement *request;
@property (nonatomic, retain) NSXMLElement *response;
- (id)initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response;
- (void)dealloc;
@end

#pragma mark -

/**
 * Handles the in-order processing of responses.
 **/
@interface BoshWindowManager : NSObject <NSCoding>  {
    long long maxRidReceived; // all rid value less than equal to maxRidReceived are processed.
    long long maxRidSent;
    NSMutableSet *receivedRids;
}

@property unsigned int windowSize;
@property (readonly) long long maxRidReceived;

- (id)initWithRid:(long long)rid;
- (void)sentRequestForRid:(long long)rid;
- (void)receivedResponseForRid:(long long)rid;
- (BOOL)isWindowFull;
- (BOOL)isWindowEmpty;
- (void)dealloc;
@end


#pragma mark -

@interface BoshTransport : NSObject <XMPPTransportProtocol,NSCoding> {
    NSString *boshVersion;

    long long nextRidToSend;
    long long maxRidProcessed;
    
    NSMutableArray *pendingXMPPStanzas;
    BoshWindowManager *boshWindowManager;
    BoshTransportState state;
    
    NSMutableDictionary *requestResponsePairs;
    
    MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
    NSError *disconnectError_;
    
    int retryCounter;
    NSTimeInterval nextRequestDelay;
  
    BOOL secure;
  unsigned int requests;
}

@property(retain) XMPPJID *myJID;
@property(assign) unsigned int wait;
@property(assign) unsigned int hold;
@property(copy) NSString *lang;
@property(copy) NSString *domain;
@property(copy) NSString *routeProtocol;
@property(copy) NSString *host;
@property(assign) unsigned int port;
@property(assign) unsigned int inactivity;
@property(readonly) BOOL secure;
@property(readonly) unsigned int requests;
@property(copy) NSString *authid;
@property(copy) NSString *sid;
@property(copy) NSURL *url;
@property(readonly) NSError *disconnectError;

/* init Methods */
- (id)initWithUrl:(NSURL *)url forDomain:(NSString *)domain;
- (id)initWithUrl:(NSURL *)url
        forDomain:(NSString *)domain
    routeProtocol:(NSString *)routeProtocol
             host:(NSString *)host
             port:(unsigned int)port;
- (id)initWithUrl:(NSURL *)url
        forDomain:(NSString *)domain
     withDelegate:(id<XMPPTransportDelegate>)delegate;
- (id)initWithUrl:(NSURL *)url
        forDomain:(NSString *)domain
    routeProtocol:(NSString *)routeProtocol
             host:(NSString *)host
             port:(unsigned int)port
     withDelegate:(id<XMPPTransportDelegate>)delegate;

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
- (void)resendRemainingRequests;
@end
