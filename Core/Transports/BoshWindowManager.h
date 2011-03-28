//
//  BoshWindowManager.h
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/28/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDXML.h"

@protocol BoshWindowProtocol
- (void)broadcastStanzas:(NSXMLNode *)node;
@end

@interface BoshWindowManager : NSObject {
	NSMutableDictionary *window;
	
	u_int32_t maxRidReceived;
	u_int32_t maxRidSent;
	
	id delegate;
}

@property u_int32_t windowSize;
@property(readonly) u_int32_t outstandingRequests;

- (void)sentRequest:(NSXMLElement *)request;
- (void)recievedResponse:(NSXMLElement *)response;
- (BOOL)canSendMoreRequests;
- (BOOL)canLetServerHoldRequests:(u_int32_t)hold;
- (NSXMLElement *)getRequestForRid:(u_int32_t)rid;
- (id)initWithDelegate:(id)del rid:(u_int32_t)rid;
@end

