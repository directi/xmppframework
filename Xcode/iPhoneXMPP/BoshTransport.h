//
//  BoshTransport.h
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPTransportProtocol.h"


typedef enum  {
	DISCONNECTED = 0,
	CONNECTING = 1,
	CONNECTED = 2
} BoshConnectionState;

@interface BoshTransport : NSObject <XMPPTransportProtocol > {
	NSString *version;
	NSInteger wait;
	NSInteger hold;
	NSString *from;
	NSInteger ack;
	
	u_int32_t rid;
	NSInteger sid;
	NSString *lang;
	NSString *contentType;
	NSString *jid;
	NSInteger polling;
	NSInteger inactivity;
	NSInteger requests;
	NSString *to;
	id<XMPPTransportDelegate> delegate;
}

@property(copy) NSString *jid;
@property(retain) id<XMPPTransportDelegate> delegate;
@property(assign) NSInteger wait;
@property(assign) NSInteger hold;
@property(copy) NSString *lang;
@property(copy) NSString *contentType;

- (id)init;
- (id)initWithDelegate:(id<XMPPTransportDelegate>)delegate;
- (BOOL)connect:(NSError **)error;
- (BOOL)disconnect;
- (BOOL)sendStanza:(NSXMLElement *)stanza;

@end