#include "4DPlugin-Mail.cpp"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "ARRAY_TEXT.h"
#include <objc/runtime.h>
#include <cstdlib>
#include <cstring>
#include <set>

using Text = std::basic_string<PA_Unichar>;
static const char *scenario;
static bool nullEmpty;
static bool failHandle;
static bool failGetter;
static bool failCommand;
static bool mismatchCommand;
static bool failElement;
static bool failPathProperty;
static bool mismatchPathProperty;
static int handlesUntilFailure = -1;
static int stringsUntilFailure = -1;
static int uiCalls;

static void require(bool value, const char *message) {
    if(!value) {
        fprintf(stderr, "%s: %s\n", scenario, message);
        std::exit(1);
    }
}

static Text text(const char16_t *value) {
    Text result;
    while(*value) result.push_back(*value++);
    return result;
}

static std::map<PA_Unichar *, Text> strings;
static PA_Unistring makeString(const Text& value) {
    PA_Unistring result = {};
    if(value.empty() && nullEmpty) return result;
    result.fString = new PA_Unichar[value.size() + 1];
    std::copy(value.begin(), value.end(), result.fString);
    result.fString[value.size()] = 0;
    result.fLength = static_cast<PA_long32>(value.size());
    PA_Unichar *pointer = result.fString;
    strings.emplace(pointer, value);
    return result;
}

static Text readString(PA_Unistring value) {
    if(!value.fString) {
        require(value.fLength == 0, "null string with nonzero length");
        return {};
    }
    PA_Unichar *pointer = value.fString;
    auto found = strings.find(pointer);
    require(found != strings.end(), "read of disposed/borrowed-invalid string");
    require(value.fLength == found->second.size(), "wrong UTF-16 code-unit count");
    require(value.fString[value.fLength] == 0, "missing UTF-16 terminator");
    require(Text(value.fString, value.fLength) == found->second, "text changed");
    return found->second;
}

static void freeString(PA_Unistring value) {
    if(!value.fString) return;
    PA_Unichar *pointer = value.fString;
    require(strings.erase(pointer) == 1, "double disposal of shallow string alias");
    delete[] value.fString;
}

struct Node {
    int refs = 1;
    std::map<Text, PA_Variable> properties;
    std::vector<PA_Variable> elements;
};
static std::set<Node *> nodes;
static Node *newNode() {
    Node *node = new Node;
    nodes.insert(node);
    return node;
}
static Node *nodeFor(void *ptr) {
    Node *node = static_cast<Node *>(ptr);
    require(nodes.count(node) != 0, "dead object/collection reference");
    return node;
}
static void clear(PA_Variable& value);
static void release(void *ptr) {
    if(!ptr) return;
    Node *node = nodeFor(ptr);
    if(--node->refs) return;
    for(auto& property : node->properties) clear(property.second);
    for(auto& element : node->elements) clear(element);
    nodes.erase(node);
    delete node;
}
static PA_Variable copy(PA_Variable value) {
    if(value.fType == eVK_Unistring) value.uValue.fString = makeString(readString(value.uValue.fString));
    if(value.fType == eVK_Object && value.uValue.fObject) ++nodeFor(value.uValue.fObject)->refs;
    if(value.fType == eVK_Collection && value.uValue.fCollection) ++nodeFor(value.uValue.fCollection)->refs;
    if(value.fType == eVK_Picture && value.uValue.fPicture) ++nodeFor(value.uValue.fPicture)->refs;
    return value;
}
static std::map<PA_Handle, size_t> handles;
static void clear(PA_Variable& value) {
    switch(value.fType) {
        case eVK_Unistring: freeString(value.uValue.fString); break;
        case eVK_Object: release(value.uValue.fObject); break;
        case eVK_Collection: release(value.uValue.fCollection); break;
        case eVK_Picture: release(value.uValue.fPicture); break;
        case eVK_ArrayUnicode: {
            auto handle = value.uValue.fArray.fData;
            require(handles.count(handle), "invalid array handle");
            auto elements = reinterpret_cast<PA_Unistring *>(*handle);
            for(int i = 0; i <= value.uValue.fArray.fNbElements; ++i) freeString(elements[i]);
            PA_DisposeHandle(handle);
            break;
        }
        case eVK_Undefined:
        case eVK_Null:
        case eVK_Boolean:
        case eVK_Longint:
        case eVK_Real: break;
        default: require(false, "clear of failed/uninitialized/raw-kind0 result");
    }
    value = {};
    value.fType = eVK_Undefined;
}
static PA_Variable stringValue(const Text& value) {
    PA_Variable result = {};
    result.fType = eVK_Unistring;
    result.uValue.fString = makeString(value);
    return result;
}
static PA_Variable refValue(Node *node, PA_VariableKind kind) {
    PA_Variable result = {};
    if(kind == eVK_Object) PA_SetObjectVariable(&result, node);
    else PA_SetCollectionVariable(&result, node);
    return result;
}
static Text key(const char16_t *value) { return text(value); }
static void property(Node *node, const char16_t *name, PA_Variable value) {
    auto old = node->properties.find(key(name));
    if(old != node->properties.end()) clear(old->second);
    node->properties[key(name)] = value;
}
static NSString *ns(const Text& value) {
    return [[[NSString alloc] initWithCharacters:value.data() length:value.size()] autorelease];
}
static CUTF8String utf8(const Text& value) {
    NSData *data = [ns(value) dataUsingEncoding:NSUTF8StringEncoding];
    return CUTF8String(static_cast<const uint8_t *>([data bytes]), [data length]);
}
static NSArray *expectedRecipients;
static NSArray *expectedAttachments;
static NSString *expectedBody;
@interface MailSink : NSObject
@property(copy) NSString *subject;
@property(copy) NSArray *recipients;
- (void)performWithItems:(NSArray *)items;
@end
@implementation MailSink
@synthesize subject, recipients;
- (void)performWithItems:(NSArray *)items {
    require([self.recipients isEqual:expectedRecipients], "recipient content/count differs");
    require([self.subject isEqual:expectedBody], "subject content differs");
    require([items count] == [expectedAttachments count] + 1, "body/attachment count differs");
    require([[items objectAtIndex:0] isEqual:expectedBody], "body content differs");
    for(NSUInteger i = 0; i < [expectedAttachments count]; ++i) {
        require([[[items objectAtIndex:i + 1] path] isEqual:[expectedAttachments objectAtIndex:i]],
                "attachment path differs");
    }
    ++uiCalls;
}
- (void)dealloc {
    [subject release];
    [recipients release];
    [super dealloc];
}
@end
static id sharingStub(id, SEL, id) { return [[[MailSink alloc] init] autorelease]; }

static void engine(short selector, EngineBlock *eb) {
    eb->fError = eER_NoErr;
    switch(selector) {
        case EX_CREATE_UNISTRING: {
            if(stringsUntilFailure == 0) {
                stringsUntilFailure = -1;
                memset(&eb->fUniString1, 0xa5, sizeof(eb->fUniString1));
                eb->fError = eER_NotEnoughMemory;
                return;
            }
            if(stringsUntilFailure > 0) --stringsUntilFailure;
            auto ptr = reinterpret_cast<PA_Unichar *>(eb->fHandle);
            require(ptr != nullptr, "string constructor requires a terminated input buffer");
            eb->fUniString1 = makeString(Text(ptr));
            break;
        }
        case EX_DISPOSE_UNISTRING: freeString(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            Text value(reinterpret_cast<PA_Unichar *>(eb->fHandle));
            freeString(eb->fUniString1);
            eb->fUniString1 = makeString(value);
            break;
        }
        case EX_VARIABLE_TO_STRING: {
            auto value = reinterpret_cast<PA_Variable *>(eb->fHandle);
            require(value->fType == eVK_Unistring, "string getter on failed/wrong-kind result");
            readString(value->uValue.fString);
            eb->fUniString1 = value->uValue.fString;
            break;
        }
        case EX_CLEAR_VARIABLE: clear(*static_cast<PA_Variable *>(eb->fPtr1)); break;
        case EX_CREATE_PICTURE: eb->fPicture = newNode(); break;
        case EX_DISPOSE_PICTURE: release(eb->fPicture); break;
        case EX_HANDLE_MANAGER: {
            PA_Handle handle = eb->fParam1 == 1 ? nullptr : eb->fHandle;
            switch(eb->fParam1) {
                case 1:
                    if(failHandle || handlesUntilFailure == 0) {
                        failHandle = false;
                        handlesUntilFailure = -1;
                        eb->fHandle = nullptr;
                        eb->fError = eER_NotEnoughMemory;
                    }else{
                        if(handlesUntilFailure > 0) --handlesUntilFailure;
                        auto h = new char *;
                        size_t size = eb->fParam2;
                        *h = static_cast<char *>(calloc(std::max<size_t>(size, 1), 1));
                        handles[h] = eb->fParam2;
                        eb->fHandle = h;
                    }
                    break;
                case 2:
                    require(handles.erase(handle) == 1, "invalid/disposed handle");
                    free(*eb->fHandle);
                    delete eb->fHandle;
                    break;
                case 3: {
                    require(handles.count(handle), "resize invalid handle");
                    size_t size = eb->fParam2;
                    *handle = static_cast<char *>(realloc(*handle, std::max<size_t>(size, 1)));
                    handles[handle] = size;
                    break;
                }
                case 4:
                    require(handles.count(handle), "size invalid handle");
                    eb->fParam2 = handles.at(handle);
                    break;
                case 5:
                    require(handles.count(handle), "lock invalid handle");
                    eb->fParam3 = reinterpret_cast<sLONG_PTR>(*eb->fHandle);
                    break;
                case 6: require(handles.count(handle), "unlock invalid handle"); break;
                default: require(false, "unhandled handle operation");
            }
            break;
        }
        case EX_GET_OBJ_VALUE: {
            auto result = static_cast<PA_Variable *>(eb->fPtr2);
            bool pathProperty = eb->fShort == eVK_Object && readString(eb->fUniString1) == key(u"path");
            if(failGetter || (failElement && eb->fShort == eVK_Collection && eb->fLongint >= 0)
                    || (failPathProperty && pathProperty)) {
                // A failed getter does not promise to initialize its output.
                memset(result, 0xa5, sizeof(*result));
                eb->fError = eER_IncompatibleTypes;
                return;
            }
            Node *node = nodeFor(eb->fPtr1);
            if(eb->fShort == eVK_Object) {
                if(mismatchPathProperty && pathProperty) {
                    *result = refValue(newNode(), eVK_Object);
                    break;
                }
                auto found = node->properties.find(readString(eb->fUniString1));
                require(found != node->properties.end(), "unknown fixture property");
                *result = copy(found->second);
            }else if(eb->fLongint == -1) {
                PA_SetLongintVariable(result, static_cast<PA_long32>(node->elements.size()));
            }else{
                require(eb->fLongint >= 0 && eb->fLongint < node->elements.size(), "bad collection index");
                *result = copy(node->elements.at(eb->fLongint));
            }
            break;
        }
        case EX_SET_OBJ_VALUE: {
            Node *node = nodeFor(eb->fPtr1);
            Text name = readString(eb->fUniString1);
            auto old = node->properties.find(name);
            if(old != node->properties.end()) clear(old->second);
            node->properties[name] = copy(*static_cast<PA_Variable *>(eb->fPtr2));
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: {
            auto args = static_cast<PA_Variable **>(eb->fPtr1);
            auto result = static_cast<PA_Variable *>(eb->fPtr2);
            if(failCommand) { eb->fError = eER_IncompatibleTypes; return; }
            switch(eb->fParam1) {
                case 1231:
                case 1230: {
                    Node *node = nodeFor(args[0]->uValue.fObject);
                    auto found = node->properties.find(readString(args[1]->uValue.fString));
                    if(eb->fParam1 == 1231) PA_SetBooleanVariable(result, found != node->properties.end());
                    else PA_SetLongintVariable(result, found == node->properties.end() ? eVK_Undefined : found->second.fType);
                    break;
                }
                case 1566:
                case 1567: {
                    Text path = readString(args[0]->uValue.fString);
                    if(mismatchCommand) { *result = stringValue(path); break; }
                    Node *node = newNode();
                    property(node, u"path", stringValue(path));
                    *result = refValue(node, eVK_Object);
                    break;
                }
                case 1225:
                    // OB Copy creates an independent object with copied values.
                    *result = refValue(newNode(), eVK_Object);
                    for(auto& item : nodeFor(args[0]->uValue.fObject)->properties)
                        nodeFor(result->uValue.fObject)->properties[item.first] = copy(item.second);
                    break;
                case 1217: *result = stringValue(key(u"{}")); break;
                default: require(false, "unhandled command");
            }
            break;
        }
        case EX_RUN_IN_MAIN_PROCESS:
            reinterpret_cast<PA_RunInMainProcessProcPtr>(eb->fPtr1)(eb->fPtr2);
            break;
        default: require(false, "unhandled engine selector");
    }
}

static std::vector<Text> fixtures() {
    return {text(u"ASCII"), text(u"\u65e5\u672c"), text(u"\U0001f600"), Text()};
}
static void balanced() {
    if(!strings.empty() || !nodes.empty() || !handles.empty()) {
        fprintf(stderr, "%s: outstanding strings=%zu refs=%zu handles=%zu\n",
                scenario, strings.size(), nodes.size(), handles.size());
        std::exit(1);
    }
}
static void paths(bool folder) {
    for(const auto& value : fixtures()) {
        if(folder) {
            CUTF8String u8 = utf8(value);
            std::string input(reinterpret_cast<const char *>(u8.c_str()), u8.size());
            auto ref = path_to_folder_object(input);
            require(ref != nullptr, "missing owning folder handoff");
            require(readString(nodeFor(ref)->properties.at(key(u"path")).uValue.fString) == value, "wrong folder path");
            PA_DisposeObject(ref);
        }else{
            Node *file = newNode();
            property(file, u"platformPath", stringValue(value));
            std::string output;
            require(file_object_to_path(file, output), "path conversion failed");
            auto expected = utf8(value);
            require(output == std::string(reinterpret_cast<const char *>(expected.c_str()), expected.size()), "path UTF-8 differs");
            require(readString(file->properties.at(key(u"platformPath")).uValue.fString) == value, "original path changed");
            PA_DisposeObject(file);
        }
        balanced();
    }
}
static void setters() {
    for(const auto& value : fixtures()) {
        Node *obj = newNode();
        CUTF8String u8 = utf8(value);
        ob_set_s(obj, "narrow", reinterpret_cast<const char *>(u8.c_str()));
        ob_set_s(obj, L"wide", reinterpret_cast<const char *>(u8.c_str()));
        ob_set_a(obj, L"utf16", &value);
        std::wstring wide;
        NSString *s = ns(value);
        NSData *u32 = [s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
        wide.assign(static_cast<const wchar_t *>([u32 bytes]), [u32 length] / sizeof(wchar_t));
        ob_set_a(obj, L"wchar", wide.c_str());
        ob_set_p(obj, L"picture", PA_CreatePicture(nullptr, 0));
        for(const auto& name : {u"narrow", u"wide", u"utf16", u"wchar"})
            require(readString(obj->properties.at(key(name)).uValue.fString) == value, "setter text differs");
        PA_DisposeObject(obj);
        balanced();
    }
}
static void getters() {
    for(const auto& value : fixtures()) {
        Node *obj = newNode();
        property(obj, u"value", stringValue(value));
        CUTF8String out;
        require(ob_get_a(obj, L"value", &out) && out == utf8(value), "scalar getter text differs");
        require(!ob_get_b(obj, L"value"), "boolean mismatch");
        require(ob_get_n(obj, L"value") == 0, "number mismatch");
        require(!ob_get_c(obj, L"value"), "collection mismatch");
        require(!ob_get_o(obj, L"value"), "object mismatch");
        property(obj, u"object", refValue(newNode(), eVK_Object));
        property(obj, u"collection", refValue(newNode(), eVK_Collection));
        require(ob_get_a(obj, L"object", &out), "successful mismatch changed defined status");
        require(!ob_get_b(obj, L"object") && ob_get_n(obj, L"object") == 0, "scalar mismatch");
        require(!ob_get_c(obj, L"object") && !ob_get_o(obj, L"collection"), "reference mismatch");
        PA_Variable boolean = PA_CreateVariable(eVK_Boolean);
        PA_SetBooleanVariable(&boolean, 1);
        property(obj, u"boolean", boolean);
        PA_Variable number = PA_CreateVariable(eVK_Real);
        PA_SetRealVariable(&number, 1.25);
        property(obj, u"number", number);
        require(ob_get_b(obj, L"boolean") && ob_get_n(obj, L"number") == 1.25, "scalar value differs");
        auto object = ob_get_o(obj, L"object");
        auto collection = ob_get_c(obj, L"collection");
        PA_DisposeObject(obj);
        require(nodes.count(static_cast<Node *>(object)) && nodes.count(static_cast<Node *>(collection)),
                "owning handoff died with source owner");
        PA_DisposeObject(object);
        PA_DisposeCollection(collection);
        balanced();
    }
}
static void drafts() {
    for(int count : {0, 1, 4}) {
        Node *options = newNode();
        Node *recipients = newNode();
        Node *attachments = newNode();
        NSMutableArray *expectedR = [NSMutableArray array];
        NSMutableArray *expectedA = [NSMutableArray array];
        auto values = fixtures();
        for(int i = 0; i < count; ++i) {
            recipients->elements.push_back(stringValue(values[i]));
            if(!failElement) [expectedR addObject:ns(values[i])];
            Text path = key(u"/synthetic/") + values[i] + key(u".txt");
            Node *file = newNode();
            property(file, u"platformPath", stringValue(path));
            attachments->elements.push_back(refValue(file, eVK_Object));
            if(!failElement) [expectedA addObject:ns(path)];
        }
        // Successful wrong-kind elements also own their contents.
        recipients->elements.push_back(refValue(newNode(), eVK_Object));
        attachments->elements.push_back(stringValue(key(u"ignored")));
        property(options, u"recipients", refValue(recipients, eVK_Collection));
        property(options, u"attachments", refValue(attachments, eVK_Collection));
        Text body = key(u"Body \u65e5\U0001f600");
        property(options, u"subject", stringValue(body));
        property(options, u"textBody", stringValue(body));
        expectedRecipients = expectedR;
        expectedAttachments = expectedA;
        expectedBody = ns(body);
        PA_ObjectRef ref = options;
        void *parameters[] = {&ref};
        PluginBlock params = {};
        params.fParameters = parameters;
        int previous = uiCalls;
        PluginMain(1, &params);
        require(uiCalls == previous + 1, "dispatcher did not reach stubbed sharing API");
        PA_DisposeObject(options);
        balanced();
    }
}
static void contracts() {
    PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&array, 4);
    auto values = fixtures();
    for(int i = 0; i < 4; ++i) {
        auto value = makeString(values[i]);
        PA_SetStringInArray(array, i, &value);
        require(PA_GetStringInArray(array, i).fString == value.fString, "array did not transfer descriptor");
    }
    auto borrowed = PA_GetStringInArray(array, 1);
    auto independent = makeString(readString(borrowed));
    PA_SetStringInArray(array, 4, &independent);
    auto replacement = makeString(key(u"replacement"));
    PA_SetStringInArray(array, 1, &replacement);
    require(readString(PA_GetStringInArray(array, 4)) == values[1], "borrowed copy did not survive mutation");
    for(int i : {0, 2, 3, 4})
        require(readString(PA_GetStringInArray(array, i)) == values[i == 4 ? 1 : i], "array content differs");
    PA_Unistring rejected = makeString(key(u"rejected"));
    auto pointer = rejected.fString;
    PA_Variable wrong = PA_CreateVariable(eVK_Longint);
    PA_SetStringInArray(wrong, 0, &rejected);
    PA_SetStringInArray(array, -1, &rejected);
    PA_SetStringInArray(array, 5, &rejected);
    auto noData = array;
    noData.uValue.fArray.fData = nullptr;
    PA_SetStringInArray(noData, 0, &rejected);
    PA_SetStringInArray(array, 0, nullptr);
    require(rejected.fString == pointer && readString(rejected) == key(u"rejected"), "rejection consumed caller ownership");
    PA_DisposeUnistring(&rejected);
    require(readString(PA_GetStringInArray(array, 0)) == values[0], "null descriptor changed destination");
    PA_ResizeArray(&array, 0);
    PA_ClearVariable(&array);
    balanced();

    ARRAY_TEXT wrapper;
    for(const auto& value : values) wrapper.appendUTF16String(value.c_str());
    array = PA_CreateVariable(eVK_Undefined);
    BytePtr params[] = {reinterpret_cast<BytePtr>(&array)};
    wrapper.toParamAtIndex(params, 1);
    for(int i = 0; i < 4; ++i) require(readString(PA_GetStringInArray(array, i)) == values[i], "wrapper array differs");
    ARRAY_TEXT snapshot;
    snapshot.fromParamAtIndex(params, 1);
    PA_ClearVariable(&array);
    for(int i = 0; i < 4; ++i) {
        CUTF16String value;
        snapshot.copyUTF16StringAtIndex(&value, i);
        require(value == values[i], "wrapper kept borrowed array buffer");
    }
    balanced();

    for(const auto& value : values) {
        PA_Unistring output = makeString(key(u"old"));
        PA_Unistring *result = &output;
        PluginBlock params = {};
        params.fResult = &result;
        PA_ReturnString(&params, const_cast<PA_Unichar *>(value.c_str()));
        require(readString(output) == value, "content return changed text");
        C_TEXT wrapper;
        wrapper.setUTF16String(&output);
        CUTF8String u8;
        wrapper.copyUTF8String(&u8);
        require(u8 == utf8(value), "wrapper UTF-8 bytes differ");
        PA_DisposeUnistring(&output);
        require(wrapper.getUTF16Length() == value.size(), "wrapper retained borrowed string");
        require(Text(wrapper.getUTF16StringPtr(), wrapper.getUTF16Length()) == value, "wrapper UTF-16 differs");
        balanced();
    }
}
static void failures() {
    Node *obj = newNode();
    property(obj, u"value", stringValue(key(u"owned")));
    property(obj, u"platformPath", stringValue(key(u"/synthetic/path")));
    CUTF8String out;
    failGetter = true;
    require(!ob_get_a(obj, L"value", &out), "failed string getter reported success");
    require(!ob_get_b(obj, L"value"), "failed boolean getter reported success");
    require(ob_get_n(obj, L"value") == 0, "failed numeric getter reported success");
    require(!ob_get_c(obj, L"value") && !ob_get_o(obj, L"value"), "failed ref getter reported success");
    std::string path;
    require(!file_object_to_path(obj, path), "failed path getter reported success");
    failGetter = false;
    failPathProperty = true;
    require(!file_object_to_path(obj, path), "failed nested path getter reported success");
    failPathProperty = false;
    mismatchPathProperty = true;
    require(!folder_object_to_path(obj, path), "wrong-kind nested path getter reported success");
    mismatchPathProperty = false;
    stringsUntilFailure = 1; // platformPath key succeeds; independent argument fails.
    require(!file_object_to_path(obj, path), "failed argument allocation reported success");
    stringsUntilFailure = 0;
    require(!path_to_folder_object(path), "failed path allocation reported success");
    for(int mode = 0; mode < 3; ++mode) {
        failCommand = mode == 0;
        mismatchCommand = mode == 1;
        // Fail specifically the command parameter handle, after the property-type
        // command has run, by exercising the dormant direct constructor.
        failHandle = mode == 2;
        std::string input = "/synthetic/path";
        require(!path_to_folder_object(input), "failed folder command reported success");
        failCommand = mismatchCommand = false;
    }
    handlesUntilFailure = 1; // OB Copy succeeds; JSON Stringify's handle fails.
    ob_stringify(obj, &out);
    failCommand = true;
    ob_stringify(obj, &out);
    failCommand = false;
    ob_stringify(obj, &out);
    require(out == CUTF8String(reinterpret_cast<const uint8_t *>("{}")), "stringify content differs");
    PA_DisposeObject(obj);
    balanced();
    failElement = true;
    drafts();
    failElement = false;
}
static void commandFailure() {
    Node *obj = newNode();
    CUTF8String out(reinterpret_cast<const uint8_t *>("unchanged"));
    handlesUntilFailure = 1;
    ob_stringify(obj, &out);
    require(out == CUTF8String(reinterpret_cast<const uint8_t *>("unchanged")),
            "failed command changed caller output");
    PA_DisposeObject(obj);
    balanced();
}
int main(int argc, char **argv) {
    @autoreleasepool {
        require(argc == 3, "expected scenario and empty representation");
        scenario = argv[1];
        nullEmpty = std::string(argv[2]) == "null";
        gCall4D = engine;
        Method factory = class_getClassMethod([NSSharingService class], @selector(sharingServiceNamed:));
        require(factory != nullptr, "sharing API unavailable");
        method_setImplementation(factory, reinterpret_cast<IMP>(sharingStub));
        if(std::string(scenario) == "path") paths(false);
        else if(std::string(scenario) == "folder") paths(true);
        else if(std::string(scenario) == "setters") setters();
        else if(std::string(scenario) == "getters") getters();
        else if(std::string(scenario) == "draft") drafts();
        else if(std::string(scenario) == "contracts") contracts();
        else if(std::string(scenario) == "failures") failures();
        else if(std::string(scenario) == "command") commandFailure();
        else require(false, "unknown scenario");
        printf("%s (%s): exact content and zero string/ref/handle balances\n", scenario, argv[2]);
    }
}
