//
//  BoshWindowManager.m
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/28/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "BoshWindowManager.h"

@interface RequestResponsePair : NSObject
{
}

@property(retain) NSXMLElement *request;
@property(retain) NSXMLElement *response;
- (id)initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response;
- (void)dealloc;
@end

@implementation RequestResponsePair

@synthesize request=request_;
@synthesize response=response_;

- (id) initWithRequest:(NSXMLElement *)request response:(NSXMLElement *)response
{
	if( self = [super init]) {
		request_ = request;
		response_ = response;
	}
	return self;
}

- (void)dealloc
{
	[request_ release];
	[response_ release];
	[super dealloc];
}
@end


@implementation BoshWindowManager

@synthesize windowSize;
@synthesize outstandingRequests;

- (u_int32_t)getRidInBody:(NSXMLElement *)body
{
    return [[[body attributeForName:@"rid"] stringValue] intValue];
}

- (NSString *)stringFromInt:(u_int32_t)num
{
	return [NSString stringWithFormat:@"%u",num];
}

- (id)initWithDelegate:(id)del rid:(u_int32_t)rid
{
	if(self = [super init])
	{
		window = [[NSMutableDictionary alloc] initWithCapacity:4];
		windowSize = 0;
		outstandingRequests = 0;
		maxRidSent = rid;
		maxRidReceived = rid;
		delegate = del;
	}
	return self;
}

- (void)sentRequest:(NSXMLElement *)request
{
	NSAssert( [self canSendMoreRequests], @"Sending request when should not be: Exceeding request count" );
	u_int32_t requestRid = [self getRidInBody:request];
	NSAssert ( requestRid == maxRidSent + 1, @"Sending request with rid = %u greater than expected rid = %u", requestRid, maxRidSent + 1);
	++maxRidSent;
	[window setValue:[[RequestResponsePair alloc] initWithRequest:request response:nil] forKey:[self stringFromInt:requestRid]];
}

- (void)processResponses
{
	while (true)
	{
		RequestResponsePair *requestResponsePair = [window valueForKey:[self stringFromInt:(maxRidReceived+1)]];
		if( requestResponsePair.response == nil ) break;
		[[requestResponsePair.response retain] autorelease];
		[window removeObjectForKey:[ self stringFromInt:(maxRidReceived + 1) ]];
		++maxRidReceived;
		[delegate broadcastStanzas:requestResponsePair.response];
	}
}
	 
- (void)recievedResponse:(NSXMLElement *)response
{
	u_int32_t responseRid = [self getRidInBody:response];
	NSAssert(responseRid > maxRidReceived, @"Recieving response for rid = %u where maxRidReceived = %u", responseRid, maxRidReceived);
	NSAssert(responseRid < maxRidReceived + windowSize, @"Recieved response for a request outside the rid window. responseRid = %u, maxRidReceived = %u, windowSize = %u", responseRid, maxRidReceived, windowSize);
	RequestResponsePair *requestResponsePair = [window valueForKey:[self stringFromInt:responseRid]];
	NSAssert( requestResponsePair != nil, @"Response rid not in queue");
	requestResponsePair.response = response;
	[self processResponses];
}

- (BOOL)canSendMoreRequests
{
	return (maxRidSent - maxRidReceived) < windowSize;
}

- (BOOL)canLetServerHoldRequests:(u_int32_t)hold
{
	return (maxRidSent - maxRidReceived) < hold;
}
- (NSXMLElement *)getRequestForRid:(u_int32_t)rid
{
	NSAssert( rid - maxRidReceived > 0 && [window count] > (rid - maxRidReceived), @"Error Access request for rid = %u, where maxRidReceived = %u and [requestQueue count] = %u", rid, maxRidReceived, [window count]);
	return [window valueForKey:[self stringFromInt:rid]];
}

@end
