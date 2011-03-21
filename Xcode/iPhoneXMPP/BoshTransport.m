//
//  BoshTransport.m
//  iPhoneXMPP
//
//  Created by Satyam Shekhar on 3/17/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "BoshTransport.h"
#import "DDXML.h"
#import "NSXMLElementAdditions.h"

@interface BoshTransport()
- (void) sendData;
- (u_int32_t) generateRid;
- (NSString *) newRequestWithPayload:(NSXMLElement *)payload attributes:(NSArray *)attributes namespaces:(NSArray *)namespaces;
- (NSArray *) createAttribureArrayFromDictionary:(NSDictionary *)attributes;
- (NSArray *) createNamespaceArrayFromDictionary:(NSDictionary *)namespacesDictionary;
@end

@implementation BoshTransport

@synthesize jid;
@synthesize delegate;
@synthesize wait;
@synthesize hold;
@synthesize lang;
@synthesize contentType;

- (u_int32_t) generateRid {
	return (arc4random() % 1000000000LL + 1000000001LL);
}

- (NSArray *) createArrayFromDictionary:(NSDictionary *)dictionary of:(NSString *)type {
	NSMutableArray *array = [[NSMutableArray alloc] init];
	NSString *key;
	for (key in dictionary) {
		NSString *value = [dictionary objectForKey:key];
		NSXMLNode *node;
		if([type isEqualToString:@"attributes"]) {
			node = [NSXMLNode attributeWithName:key stringValue:value];
		}
		else {
			node = [NSXMLNode namespaceWithName:key stringValue:value];
		}
		[array addObject:node];
	}
	return array;	
}

- (NSArray *) createArributeArrayFromDictionary:(NSDictionary *)attributesDictionary {
	return [self createArrayFromDictionary:attributesDictionary of:@"attributes"];
}

- (NSArray *) createNamespaceArrayFromDictionary:(NSDictionary *)namespacesDictionary {
	return [self createArrayFromDictionary:namespacesDictionary of:@"namespaces"];
}

-(NSString *) newRequestWithPayload:(NSXMLElement *)payload attributes:(NSArray *)attributes namespaces:(NSArray *)namespaces {
	NSXMLElement *boshRequest = [[NSXMLElement alloc] initWithName:@"body"];
	
	[boshRequest setNamespaces:namespaces];
	[boshRequest setAttributes:attributes];
	[boshRequest addChild:payload];
	
	NSString *serializedRequest = [boshRequest compactXMLString];
	[boshRequest release];
	return serializedRequest;
}

- (void) sendData {
	return;
}

- (id) init {
	return [self initWithDelegate:nil];
}

- (id)initWithDelegate:(id<XMPPTransportDelegate>)delegateToSet {
	self = [super init];
	if(self) {
		version = @"1.6";
		lang = @"en";
		contentType = @"text/xml; charset=utf-8";
		wait = 60;
		hold = 1;
		ack = 1;
		
		rid = [self generateRid];
		delegate = delegateToSet;
		
		sid = 0;
		polling = 0;
		inactivity = 0;
		requests = 0;
	}
	return self;
}
	
- (BOOL)connect:(NSError **)error {
	NSArray *objects = [[NSArray alloc] initWithObjects:@"content", @"hold", @"rid", @"to", @"ver", @"wait", @"ack", @"xml:lang", nil];
	NSArray *keys = [[NSArray alloc] initWithObjects:contentType, [NSString stringWithFormat:@"%d", hold], [NSString stringWithFormat:@"%d", rid],  ;
	NSDictionary *headers = [[NSDictionary alloc] initWithObjects:objects forKeys:keys];
	[self newRequestWithPayload:nil attributes:headers];
	return TRUE;
}

- (BOOL)disconnect {
	return TRUE;
};

- (BOOL) sendStanza:(NSXMLElement *)stanza {
	return TRUE;
}

@end
