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
@property(copy) NSString *host;
@property(readonly) NSNumber *inactivity;
@property(readonly) BOOL secure;
@property(readonly) NSNumber *requests;
@property(copy) NSString *authid;
@property(copy) NSString *sid;
@property(copy) NSString *url;

/* init Methods */
- (id)initWithUrl:(NSString *)url forHost:(NSString *)host;
- (id)initWithUrl:(NSString *)url forHost:(NSString *)host withDelegate:(id<XMPPTransportDelegate>)delegate;

/* ASI http methods */
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
- (void)sessionResponseHandler:(ASIHTTPRequest *)request;
@end
