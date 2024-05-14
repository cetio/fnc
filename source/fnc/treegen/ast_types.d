module fnc.treegen.ast_types;

import fnc.tokenizer.tokens : Token;
import tern.typecons.common : Nullable, nullable;

struct NamedUnit
{
    dchar[][] names;
}

enum AstAction
{
    // Typical code actions:

    Keyword, // Standalong keywords Ex: import std.std.io;
    Scope,

    IfStatement,
    ElseIfStatement,
    ElseStatement,
    ReturnStatement,

    WhileLoop,

    AssignVariable, // Ex: x = 5;
    ArrayGrouping, // [...]
    IndexInto, // X[N]

    SingleArgumentOperation, // Ex: x++, ++x
    DoubleArgumentOperation, // Ex: 9+10 

    GenericOf, // Not to be confused with TypeGeneric, ex: foo!bar(), foo!(bar)(), or "auto x classFoo!bar";
    Call, // Ex: foo(bar);

    // Misc tokens: 

    Expression, // Ex: (4+5*9)
    NamedUnit, // Ex: std.io
    LiteralUnit, // Ex: 6, 6L, "Hello world"

    TokenHolder, // A temporary Node that is yet to be parsed 
}

bool isExpressionLike(AstAction action)
{
    return action == AstAction.Expression
        || action == AstAction.ArrayGrouping;
}

bool isCallable(AstAction action)
{
    return action == AstAction.DoubleArgumentOperation
        || action == AstAction.SingleArgumentOperation
        || action == AstAction.Call
        || action == AstAction.Expression
        || action == AstAction.GenericOf
        || action == AstAction.LiteralUnit
        || action == AstAction.NamedUnit;
}

struct KeywordNodeData
{
    dchar[] keywordName;
    dchar[][] possibleExtras;
    Token[] keywardArgs;
}

struct AssignVariableNodeData
{
    AstNode[] name; // Name of variable(s) to assign Ex: x = y = z = 5;
    AstNode value;
}

enum OperationVariety
{
    PreIncrement,
    PostIncrement,
    PreDecrement,
    PostDecrement,
    // AbsuluteValue,
    // Magnitude,

    Add,
    Substract,
    Multiply,
    Divide,
    Mod,

    AddEq,
    SubstractEq,
    MultiplyEq,
    DivideEq,
    ModEq,

    Pipe,
    Assignment,

    BitwiseNot,
    BitwiseOr,
    BitwiseXor,
    BitwiseAnd,

    BitwiseNotEq,
    BitwiseOrEq,
    BitwiseXorEq,
    BitwiseAndEq,

    BitshiftLeftSigned,
    BitshiftRightSigned,
    BitshiftLeftUnSigned,
    BitshiftRightUnSigned,

    BitshiftLeftSignedEq,
    BitshiftRightSignedEq,
    BitshiftLeftUnSignedEq,
    BitshiftRightUnSignedEq,

    LogicalOr,
    LogicalAnd,
    LogicalNot,

    GreaterThan, // >
    GreaterThanEq,
    LessThan, // <
    LessThanEq,
    EqualTo,
    NotEqualTo,

    Period, // foo.bar
    Arrow, // foo->bar
    Range, // x..y OR 0..99
}

import fnc.treegen.scope_parser : ScopeData;

struct ConditionNodeData
{
    dchar[][] precedingKeywords;
    bool isScope;
    AstNode condition;
    union
    {
        ScopeData conditionScope;
        AstNode conditionResultNode;
    }
}

struct ElseNodeData
{
    dchar[][] precedingKeywords;
    bool isScope;
    union
    {
        ScopeData elseScope;
        AstNode elseResultNode;
    }
}

struct SingleArgumentOperationNodeData
{
    OperationVariety operationVariety;
    AstNode value;
}

struct DoubleArgumentOperationNodeData
{
    OperationVariety operationVariety;
    AstNode left;
    AstNode right;
}

struct ExpressionNodeData
{
    dchar opener;
    dchar closer;
    AstNode[] components;
}

struct IndexIntoNodeData
{
    AstNode indexInto;
    AstNode index;
}
/+++ These are the act of calling a function ++++/
struct FunctionCallArgument
{
    Nullable!(dchar[]) specifiedName = Nullable!(dchar[])(null);
    AstNode source;
}

struct CallNodeData
{
    AstNode func;
    FunctionCallArgument[] args;
}
/+++++++/

struct GenericNodeData // Generic used in code. Ex: foo.bar!baz
{
    AstNode symbolUsedAsGeneric;
    AstNode genericData;
}

class AstNode
{
    AstAction action;
    union
    {
        KeywordNodeData keywordNodeData; // Keyword
        AssignVariableNodeData assignVariableNodeData; // AssignVariable

        ConditionNodeData conditionNodeData; // IfStatement
        ElseNodeData elseNodeData;

        SingleArgumentOperationNodeData singleArgumentOperationNodeData; // SingleArgumentOperation
        DoubleArgumentOperationNodeData doubleArgumentOperationNodeData; // DoubleArgumentOperation
        CallNodeData callNodeData; // Call
        ExpressionNodeData expressionNodeData; // Expression
        NamedUnit namedUnit; // NamedUnit
        Token[] literalUnitCompenents; // LiteralUnit
        Token tokenBeingHeld; // TokenHolder

        AstNode nodeToReturn; // ReturnStatement
        IndexIntoNodeData indexIntoNodeData; // IndexInto

        GenericNodeData genericNodeData; // GenericOf

        AstNode voidableType;
    }

    static AstNode VOID_NAMED_UNIT()
    {
        AstNode voidNamedUnit = new AstNode();
        voidNamedUnit.action = AstAction.NamedUnit;
        import fnc.tokenizer.tokens : makeUnicodeString;

        voidNamedUnit.namedUnit = NamedUnit(["void".makeUnicodeString]);
        return voidNamedUnit;
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        import std.conv;

        sink(action.to!string);
        sink("{");
        switch (action)
        {
            case AstAction.Keyword:
                sink(keywordNodeData.to!string);
                break;
            case AstAction.TokenHolder:
                sink(tokenBeingHeld.to!string);
                break;
            case AstAction.Expression:
                sink(expressionNodeData.components.to!string);
                break;
            case AstAction.NamedUnit:
                sink(namedUnit.names.to!string);
                break;
            case AstAction.Call:
                sink(callNodeData.func.to!string);
                sink("(");
                sink(callNodeData.args.to!string);
                sink(")");
                break;
            case AstAction.LiteralUnit:
                sink(literalUnitCompenents.to!string);
                break;
            case AstAction.DoubleArgumentOperation:
                sink(doubleArgumentOperationNodeData.operationVariety.to!string);
                sink(", ");
                sink(doubleArgumentOperationNodeData.left.to!string);
                sink(", ");
                sink(doubleArgumentOperationNodeData.right.to!string);
                break;
            default:
                break;
        }
        sink("}");
    }

    void tree() => tree(-1);

    void tree(size_t tabCount)
    {
        import std.stdio;
        import std.conv;

        alias printTabs() = {
            if (tabCount != -1)
            {
                foreach (i; 0 .. tabCount)
                    write("|  ");
                write("┼ ");
            }
        };
        printTabs();

        switch (action)
        {
            case AstAction.GenericOf:
                write(action);
                writeln(":");
                genericNodeData.symbolUsedAsGeneric.tree(tabCount + 1);
                genericNodeData.genericData.tree(tabCount + 1);
                break;
      
            case AstAction.Call:
                writeln("Calling function resolved from:");
                callNodeData.func.tree(tabCount + 1);
                printTabs();
                write("With Params (");
                write(callNodeData.args.length);
                writeln(")");
                foreach (arg; callNodeData.args)
                {
                    if (arg.specifiedName != null)
                    {
                        printTabs();
                        arg.specifiedName.value.write();
                        ": ".writeln;
                        arg.source.tree(tabCount + 2);
                    }
                    else
                        arg.source.tree(tabCount + 1);

                }

                // callNodeData.args.tree(tabCount + 1);
                break;
            case AstAction.DoubleArgumentOperation:
                write("opr ");
                writeln(doubleArgumentOperationNodeData.operationVariety.to!string ~ ":");
                doubleArgumentOperationNodeData.left.tree(tabCount + 1);
                doubleArgumentOperationNodeData.right.tree(tabCount + 1);
                break;
            case AstAction.SingleArgumentOperation:
                writeln(singleArgumentOperationNodeData.operationVariety.to!string ~ ":");
                singleArgumentOperationNodeData.value.tree(tabCount + 1);
                break;
            case AstAction.IndexInto:
                writeln("Index into:");
                tabCount++;
                printTabs();
                writeln("This:");
                indexIntoNodeData.indexInto.tree(tabCount + 1);
                printTabs();
                writeln("With this:");
                indexIntoNodeData.index.tree(tabCount + 1);
                tabCount--;
                break;

            case AstAction.Expression:
                writeln(
                    "Result of expression with " ~ expressionNodeData.components.length.to!string ~ " components:");
                foreach (subnode; expressionNodeData.components)
                {
                    subnode.tree(tabCount + 1);
                }
                break;
            case AstAction.ReturnStatement:
                writeln(action);
                nodeToReturn.tree(tabCount + 1);
                break;
            case AstAction.AssignVariable:
                write("Assigning variable(s): ");
                foreach (AstNode nameNode; assignVariableNodeData.name)
                    write(nameNode.namedUnit.names.to!string ~ ", ");
                writeln(": ");
                assignVariableNodeData.value.tree(tabCount + 1);
                break;
            case AstAction.IfStatement:
                write(action);
                writeln(" hasScope = " ~ conditionNodeData.isScope.to!string ~ " keywords = " ~ conditionNodeData
                        .precedingKeywords.to!string);
                conditionNodeData.condition.tree(tabCount + 1);
                if (conditionNodeData.isScope)
                {
                    import fnc.treegen.scope_parser : tree;

                    conditionNodeData.conditionScope.tree(tabCount + 1);
                }
                else
                    conditionNodeData.conditionResultNode.tree(tabCount + 1);

                // printTabs();
                break;
            case AstAction.ElseStatement:
                write(action);
                writeln(" hasScope = " ~ elseNodeData.isScope.to!string ~ " keywords = " ~ elseNodeData
                        .precedingKeywords.to!string);
                if (elseNodeData.isScope)
                {
                    import fnc.treegen.scope_parser : tree;

                    elseNodeData.elseScope.tree(tabCount + 1);
                }
                else
                    elseNodeData.elseResultNode.tree(tabCount + 1);
                break;
            default:
                writeln(this.to!string);
                break;
        }
    }
}

private void getRelatedTokensFromNodes(AstNode[] nodes, ref Token[] output)
{
    foreach (AstNode node; nodes)
    {
        getRelatedTokens(node, output);
    }
}

void getRelatedTokens(AstNode node, ref Token[] output)
{
    switch (node.action)
    {
        // TODO: Improve all of this
        case AstAction.SingleArgumentOperation:
            getRelatedTokens(node.singleArgumentOperationNodeData.value, output);
            break;
        case AstAction.DoubleArgumentOperation:
            getRelatedTokens(node.doubleArgumentOperationNodeData.left, output);
            getRelatedTokens(node.doubleArgumentOperationNodeData.right, output);
            break;
        case AstAction.LiteralUnit:
            output ~= node.literalUnitCompenents;
            break;
        case AstAction.TokenHolder:
            output ~= node.tokenBeingHeld;
            break;
        default:
            break;
    }
}

void getMinMax(AstNode node, ref size_t minV, ref size_t maxV)
{
    Token[] tokens;
    getRelatedTokens(node, tokens);
    foreach (Token token; tokens)
    {
        import std.algorithm : min, max;

        minV = min(minV, token.startingIndex);
        maxV = max(maxV, token.startingIndex);
    }
}

import std.container.array;

bool isWhite(const AstNode node)
{
    import fnc.tokenizer.tokens : TokenType;

    return node.action == AstAction.TokenHolder &&
        (node.tokenBeingHeld.tokenVariety == TokenType.WhiteSpace
                || node.tokenBeingHeld.tokenVariety == TokenType.Comment);
}

Nullable!AstNode nextNonWhiteNode(Array!AstNode nodes, ref size_t index)
{
    Nullable!AstNode found;
    while (nodes.length > index)
    {
        AstNode node = nodes[index++];
        if (node.isWhite)
            continue;
        found = node;
        break;
    }
    return found;
}

Nullable!AstNode nextNonWhiteNode(AstNode[] nodes, ref size_t index)
{
    Nullable!AstNode found;
    while (nodes.length > index)
    {
        AstNode node = nodes[index++];
        if (node.isWhite)
            continue;
        found = node;
        break;
    }
    return found;
}
