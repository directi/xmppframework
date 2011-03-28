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
#import "BoshWindowManager.h"

typedef enum  {
	DISCONNECTED = 0,
	CONNECTING = 1,
	CONNECTED = 2
} BoshConnectionState;

@interface BoshTransport : NSObject <XMPPTransportProtocol, BoshWindowProtocol > {
	NSString *boshVersion;
	NSNumber *wait;
	NSNumber *hold;
	NSString *from;
	NSNumber *ack;

	NSString *sid;
	NSString *lang;
	NSString *content;
	XMPPJID *myJID;
	NSNumber *polling;
	NSNumber *inactivity;
	NSNumber *requests;
	NSString *to;
       
        NSString *STREAM_NS;
        NSString *CLIENT_NS;
        NSString *STANZA_NS;
        NSString *SASL_NS;
        NSString *BIND_NS;
        NSString *SESSION_NS;
        NSString *BODY_NS;
        NSString *XMPP_NS;
        
        u_int32_t nextRidToSend;
	
	NSMutableArray *pendingXMPPStanzas;
	BoshWindowManager *boshWindowManager;
        
	BOOL secure;
	NSString *boshUrl;
	MulticastDelegate <XMPPTransportDelegate> *multicastDelegate;
}

@property(retain) XMPPJID *myJID;
@property(retain) NSNumber *wait;
@property(retain) NSNumber *hold;
@property(copy) NSString *lang;
@property(copy) NSString *content;
@property(copy) NSString *host;
@property(readonly) NSNumber *inactivity;
@property(readonly) BOOL secure;
@property(readonly) NSString *authid;
@property(readonly) NSString *sid;
@property(readonly) NSNumber *requests;

/* init Methods */
#pragma mark -
#pragma mark init Methods

- (id)initWithUrl:(NSString *)url forHost:(NSString *)host;
- (id)initWithUrl:(NSString *)url forHost:(NSString *)host withDelegate:(id<XMPPTransportDelegate>)delegate;

/* ASI http methods */
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;

/* Protocol Methods */
#pragma mark -
#pragma mark Protocol Methods

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
- (void)sessionResponseHandler:(ASIHTTPRequest *)request;
@end
