#import "LibIDN.h"
#import "stringprep.h"


static NSMutableDictionary *nodeDictionary;
static NSMutableDictionary *domainDictionary;
static NSMutableDictionary *resourceDictionary;


@implementation LibIDN

+ (void)initialize {
	if (self == [LibIDN class]) {
		nodeDictionary = [[NSMutableDictionary alloc] init];
		domainDictionary = [[NSMutableDictionary alloc] init];
		resourceDictionary = [[NSMutableDictionary alloc] init];
	}
}

+ (NSString *)prepNode:(NSString *)node
{
	if(node == nil) return nil;
	
	NSString *cachedValue = [nodeDictionary objectForKey:node];
	if (cachedValue != nil) return cachedValue;

	// Each allowable portion of a JID MUST NOT be more than 1023 bytes in length.
	// We make the buffer just big enough to hold a null-terminated string of this length. 
	char buf[1024];
	
	strncpy(buf, [node UTF8String], sizeof(buf));
	
	if(stringprep_xmpp_nodeprep(buf, sizeof(buf)) != 0) return nil;
	
	NSString *returnValue = [NSString stringWithUTF8String:buf];
	[nodeDictionary setObject:returnValue forKey:node];
	return returnValue;
}

+ (NSString *)prepDomain:(NSString *)domain
{
	if(domain == nil) return nil;
	
	NSString *cachedValue = [domainDictionary objectForKey:domain];
	if (cachedValue != nil) return cachedValue;

	// Each allowable portion of a JID MUST NOT be more than 1023 bytes in length.
	// We make the buffer just big enough to hold a null-terminated string of this length. 
	char buf[1024];
	
	strncpy(buf, [domain UTF8String], sizeof(buf));
	
	if(stringprep_nameprep(buf, sizeof(buf)) != 0) return nil;
	
	NSString *returnValue = [NSString stringWithUTF8String:buf];
	[domainDictionary setObject:returnValue forKey:domain];
	return returnValue;
}

+ (NSString *)prepResource:(NSString *)resource
{
	if(resource == nil) return nil;
	
	NSString *cachedValue = [resourceDictionary objectForKey:resource];
	if (cachedValue != nil) return cachedValue;

	// Each allowable portion of a JID MUST NOT be more than 1023 bytes in length.
	// We make the buffer just big enough to hold a null-terminated string of this length. 
	char buf[1024];
	
	strncpy(buf, [resource UTF8String], sizeof(buf));
	
	if(stringprep_xmpp_resourceprep(buf, sizeof(buf)) != 0) return nil;
	
	NSString *returnValue = [NSString stringWithUTF8String:buf];
	[resourceDictionary setObject:returnValue forKey:resource];
	return returnValue;
}

@end
