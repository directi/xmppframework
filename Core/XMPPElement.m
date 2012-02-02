#import "XMPPElement.h"
#import "XMPPJID.h"
#import "NSXMLElementAdditions.h"
#import <objc/runtime.h>


static char toKey;
static char fromKey;

@implementation XMPPElement

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encoding, Decoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#if ! TARGET_OS_IPHONE
- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
	if([encoder isBycopy])
		return self;
	else
		return [NSDistantObject proxyWithLocal:self connection:[encoder connection]];
}
#endif

- (id)initWithCoder:(NSCoder *)coder
{
	NSString *xmlString;
	if([coder allowsKeyedCoding])
	{
		xmlString = [coder decodeObjectForKey:@"xmlString"];
	}
	else
	{
		xmlString = [coder decodeObject];
	}
	
	return [super initWithXMLString:xmlString error:nil];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	NSString *xmlString = [self compactXMLString];
	
	if([coder allowsKeyedCoding])
	{
		[coder encodeObject:xmlString forKey:@"xmlString"];
	}
	else
	{
		[coder encodeObject:xmlString];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Jabber Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)elementID
{
	return [[self attributeForName:@"id"] stringValue];
}

- (NSString *)toStr
{
	return [[self attributeForName:@"to"] stringValue];
}

- (NSString *)fromStr
{
	return [[self attributeForName:@"from"] stringValue];
}

- (XMPPJID *)to
{
	// Cache the value returned by this method
	// Unfortunately we can't use instance variables here since the 
	// xmppframework changes instances of NSXMLElement directly to XMPPIQ, 
	// XMPPPresence, etc. (subclasses of XMPPElement) using object_setClass(). 
	// This forbids us from adding any instance variables to these classes.
	// See note in the implementation of +[XMPPIQ initialize] for more.
	XMPPJID *to = objc_getAssociatedObject(self, &toKey);
	if (to == nil) {
		to = [XMPPJID jidWithString:[self toStr]];
		objc_setAssociatedObject(self, &toKey, to, OBJC_ASSOCIATION_RETAIN);
	}
	return to;
}

- (XMPPJID *)from
{
	XMPPJID *from = objc_getAssociatedObject(self, &fromKey);
	if (from == nil) {
		from = [XMPPJID jidWithString:[self fromStr]];
		objc_setAssociatedObject(self, &fromKey, from, OBJC_ASSOCIATION_RETAIN);
	}
	return from;
}

@end
