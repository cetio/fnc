module fnc.treegen.scope_parser;

import fnc.tokenizer.tokens;
import fnc.treegen.ast_types;
import fnc.treegen.expression_parser;
import fnc.treegen.utils;
import fnc.treegen.relationships;
import fnc.treegen.keywords;

import tern.typecons.common : Nullable, nullable;
import std.container.array;
import fnc.errors;

struct ImportStatement {
    dchar[][] keywordExtras;
    NamedUnit namedUnit;
    NamedUnit[] importSelection; // empty for importing everything
}

struct FunctionArgument {
    dchar[][] precedingKeywords;
    Nullable!AstNode type;
    NamedUnit name;
    Nullable!AstNode maybeDefault;
}

struct DeclaredFunction {
    dchar[][] precedingKeywords;
    Nullable!(FunctionArgument[]) genericArgs;
    FunctionArgument[] args;
    dchar[][] suffixKeywords;
    NamedUnit name;
    AstNode returnType;

    Nullable!ScopeData functionScope;
}

struct DeclaredVariable {
    NamedUnit name;
    AstNode type;
}

enum ObjectType {
    Struct,
    Class,
    Tagged
}

struct ObjectDeclaration {
    Nullable!ScopeData parent;
    NamedUnit name;
    ObjectType type;

    DeclaredFunction[] declaredFunctions;
    DeclaredVariable[] declaredVariables;
    Nullable!(FunctionArgument[]) genericArgs;
}

class ScopeData {
    Nullable!ScopeData parent; // Could be the global scope

    bool isPartialModule = false;
    Nullable!NamedUnit moduleName;
    ImportStatement[] imports;

    DeclaredFunction[] declaredFunctions;
    DeclaredVariable[] declaredVariables;

    ObjectDeclaration[] declaredObjects;

    Array!AstNode instructions;

    void toString(scope void delegate(const(char)[]) sink) const {
        import std.conv;

        sink("ScopeData{isPartialModule = ");
        sink(isPartialModule.to!string);
        sink(", moduleName = ");
        if (moduleName == null)
            sink("null");
        else
            sink(moduleName.value.to!string);
        sink(", imports = ");
        sink(imports.to!string);
        sink(", declaredVariables = ");
        sink(declaredVariables.to!string);

        sink(", declaredFunctions = ");
        sink(declaredFunctions.to!string);
        sink(", instructions = ");
        sink(instructions.to!string);
        sink("}");
    }
}

struct LineVarietyTestResult {
    LineVariety lineVariety;
    size_t length;
    TokenGrepResult[] tokenMatches;
}

LineVarietyTestResult getLineVarietyTestResult(
    const(VarietyTestPair[]) scopeParseMethod, Token[] tokens, size_t index) {
    size_t temp_index = index;

    foreach (method; scopeParseMethod) {
        Nullable!(TokenGrepResult[]) grepResults = method.test.matchesToken(tokens, temp_index);
        if (null != grepResults) {
            return LineVarietyTestResult(
                method.variety, temp_index - index, grepResults.value
            );
        }
        temp_index = index;
    }

    return LineVarietyTestResult(LineVariety.SimpleExpression, -1);
}

NamedUnit[] commaSeperatedNamedUnits(Token[] tokens, ref size_t index) {
    NamedUnit[] units;
    while (true) {
        NamedUnit name = tokens.genNamedUnit(index);
        if (name.names.length == 0)
            break;
        units ~= name;
        Nullable!Token mightBeACommaN = tokens.nextNonWhiteToken(index);
        if (mightBeACommaN.ptr == null) {
            index--;
            break;
        }
        Token mightBeAComma = mightBeACommaN;
        if (mightBeAComma.tokenVariety != TokenType.Comma) {
            index--;
            break;
        }
    }
    return units;
}

private FunctionArgument[] genFunctionArgs(Token[] tokens, bool isGenericArgs = false) {
    size_t index;
    FunctionArgument[] args;

    auto argParseStyle = isGenericArgs ? FUNCTION_ARGUMENT_PARSE ~ GENERIC_ARGUMENT_PARSE
        : FUNCTION_ARGUMENT_PARSE;

    while (index < tokens.length) {
        if (tokens.nextNonWhiteToken(index) == null)
            break;
        index--;

        dchar[][] keywords = tokens.skipAndExtractKeywords(index);

        LineVarietyTestResult line = argParseStyle.getLineVarietyTestResult(tokens, index);
        if (line.lineVariety == LineVariety.SimpleExpression)
            throw new SyntaxError("Can't parse function arguments", tokens[index]);
        FunctionArgument argument;
        argument.precedingKeywords = keywords;

        bool isTypeless = LineVariety.GenericArgDeclarationTypeless == line.lineVariety
            || LineVariety.GenericArgDeclarationTypelessWithDefault == line.lineVariety;
        bool hasDefault = LineVariety.DeclarationAndAssignment == line.lineVariety
            || LineVariety.GenericArgDeclarationTypelessWithDefault == line.lineVariety;
        if (!isTypeless)
            argument.type = line.tokenMatches[0].assertAs(TokenGrepMethod.Type).type;
        else
            argument.type.ptr = null;
        argument.name = line.tokenMatches[1 - isTypeless].assertAs(TokenGrepMethod.NamedUnit).name;
        if (hasDefault) {
            auto nodes = line.tokenMatches[3 - isTypeless].assertAs(TokenGrepMethod.Glob)
                .tokens.expressionNodeFromTokens();
            if (nodes.length != 1)
                throw new SyntaxError("Function argument could not parse default value", tokens[index]);
            argument.maybeDefault = Nullable!AstNode(
                nodes[0]
            );
        }
        args ~= argument;

        index += line.length;

        if (index - 1 < tokens.length && tokens[index - 1].tokenVariety == TokenType.Comma)
            continue;
        if (index < tokens.length && tokens[index].tokenVariety == TokenType.Comma) {
            index++;
            continue;
        }

        Nullable!Token maybeComma = tokens.nextNonWhiteToken(index);

        if (maybeComma == null)
            break;

        if (maybeComma.value.tokenVariety != TokenType.Comma)
            break;
    }

    return args;
}

import std.stdio;

LineVarietyTestResult parseLine(const(VarietyTestPair[]) scopeParseMethod, Token[] tokens, ref size_t index, ScopeData parent) {
    dchar[][] keywords = tokens.skipAndExtractKeywords(index);

    LineVarietyTestResult lineVariety = getLineVarietyTestResult(scopeParseMethod, tokens, index);
    switch (lineVariety.lineVariety) {
        case LineVariety.ModuleDeclaration:
            tokens.nextNonWhiteToken(index); // Skip 'module' keyword
            parent.moduleName = tokens.genNamedUnit(index);

            parent.isPartialModule = keywords.scontains(PARTIAL_KEYWORD);

            tokens.nextNonWhiteToken(index); // Skip semicolon

            break;
        case LineVariety.TaggedDeclaration:
        case LineVariety.ClassDeclaration:
        case LineVariety.StructDeclaration:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;

            Nullable!(TokenGrepResult[]) genericArgs = lineVariety.tokenMatches[OBJECT_GENERIC].assertAs(
                TokenGrepMethod.Optional).optional;
            FunctionArgument[] genericArgsList;

            if (genericArgs != null)
                genericArgsList = genFunctionArgs(
                    genericArgs.value[0].assertAs(TokenGrepMethod.Glob).tokens, true);

            size_t temp;
            auto objScope = parseMultilineScope(
                lineVariety.lineVariety == LineVariety.TaggedDeclaration ? TAGGED_DEFINITION_PARS : OBJECT_DEFINITION_PARSE,
                lineVariety.tokenMatches[OBJECT_BODY].assertAs(TokenGrepMethod.Glob)
                    .tokens,
                    temp,
                    nullable!ScopeData(parent)
            );
            ObjectDeclaration object = ObjectDeclaration(
                nullable!ScopeData(parent),
                lineVariety.tokenMatches[OBJECT_NAME].assertAs(TokenGrepMethod.NamedUnit)
                    .name,
                    [
                        LineVariety.TaggedDeclaration : ObjectType.Tagged,
                        LineVariety.StructDeclaration : ObjectType.Struct,
                        LineVariety.ClassDeclaration : ObjectType.Class,
                    ][lineVariety.lineVariety],
                objScope.declaredFunctions,
                objScope.declaredVariables,
                genericArgs != null ? nullable(genericArgsList) : nullable!(
                    FunctionArgument[])(null)
            );
            parent.declaredObjects ~= object;
            break;
        case LineVariety.TotalImport:
            tokens.nextNonWhiteToken(index); // Skip 'import' keyword
            parent.imports ~= ImportStatement(
                keywords,
                tokens.genNamedUnit(index),
                []
            );
            tokens.nextNonWhiteToken(index); // Skip semicolon
            break;
        case LineVariety.SelectiveImport:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;

            auto statement = ImportStatement(
                keywords,
                lineVariety.tokenMatches[IMPORT_PACKAGE_NAME].assertAs(TokenGrepMethod.NamedUnit)
                    .name,
                    []
            );

            statement.importSelection ~= lineVariety
                .tokenMatches[SELECTIVE_IMPORT_SELECTIONS]
                .assertAs(TokenGrepMethod.PossibleCommaSeperated)
                .commaSeperated
                .collectNamedUnits();

            parent.imports ~= statement;
            break;
        case LineVariety.DeclarationLine:
        case LineVariety.DeclarationAndAssignment:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;

            AstNode declarationType = lineVariety.tokenMatches[DECLARATION_TYPE].assertAs(
                TokenGrepMethod.Type).type;
            NamedUnit[] declarationNames = lineVariety.tokenMatches[DECLARATION_VARS]
                .assertAs(TokenGrepMethod.PossibleCommaSeperated)
                .commaSeperated.collectNamedUnits();
            AstNode[] nameNodes;
            foreach (NamedUnit name; declarationNames) {
                parent.declaredVariables ~= DeclaredVariable(name, declarationType);
                AstNode nameNode = new AstNode();
                nameNode.action = AstAction.NamedUnit;
                nameNode.namedUnit = name;
                nameNodes ~= nameNode;
            }

            if (lineVariety.lineVariety == LineVariety.DeclarationLine)
                break;

            auto nodes = lineVariety.tokenMatches[DECLARATION_EXPRESSION]
                .assertAs(TokenGrepMethod.Glob)
                .tokens.expressionNodeFromTokens();

            if (nodes.length != 1)
                throw new SyntaxError(
                    "Expression node tree could not be parsed properly (Not reducable into single node)",
                    lineVariety.tokenMatches[DECLARATION_EXPRESSION].tokens[0]);
            AstNode result = nodes[0];
            AstNode assignment = new AstNode;
            assignment.action = AstAction.AssignVariable;
            assignment.assignVariableNodeData.name = nameNodes;
            assignment.assignVariableNodeData.value = result;

            parent.instructions ~= assignment;
            break;
        case LineVariety.TaggedUntypedItem:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;
            NamedUnit name = lineVariety.tokenMatches[0].assertAs(TokenGrepMethod.NamedUnit).name;
            parent.declaredVariables ~= DeclaredVariable(name, AstNode.VOID_NAMED_UNIT);
            break;
        case LineVariety.AbstractFunctionDeclaration:
        case LineVariety.FunctionDeclaration:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;
            size_t temp;

            Nullable!(TokenGrepResult[]) genericArgs = lineVariety.tokenMatches[FUNCTION_GENERIC_ARGS].assertAs(
                TokenGrepMethod.Optional).optional;
            FunctionArgument[] genericArgsList;

            if (genericArgs != null)
                genericArgsList = genFunctionArgs(
                    genericArgs.value[0].assertAs(TokenGrepMethod.Glob).tokens, true);

            // TODO: Once @cetio fixes tern nullables (for real this time) we can make this readable.
            Nullable!ScopeData scopeData =
                LineVariety.AbstractFunctionDeclaration == lineVariety.lineVariety ? nullable!(ScopeData)(null) : nullable!(ScopeData)(
                    parseMultilineScope(
                        FUNCTION_SCOPE_PARSE,
                        lineVariety.tokenMatches[FUNCTION_SCOPE].assertAs(TokenGrepMethod.Glob)
                        .tokens,
                        temp,
                        nullable!ScopeData(parent)
                ));
            parent.declaredFunctions ~= DeclaredFunction(
                keywords,
                genericArgs == null ? nullable!(FunctionArgument[])(null) : nullable!(
                    FunctionArgument[])(genericArgsList),
                genFunctionArgs(lineVariety.tokenMatches[FUNCTION_ARGS].assertAs(TokenGrepMethod.Glob)
                    .tokens),
                [],
                lineVariety.tokenMatches[FUNCTION_NAME].assertAs(TokenGrepMethod.NamedUnit)
                    .name,
                    lineVariety.tokenMatches[FUNCTION_RETURN_TYPE].assertAs(
                        TokenGrepMethod.Type)
                    .type,
                    scopeData
            );

            break;
        case LineVariety.ReturnStatement:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;
            auto returnNodes = expressionNodeFromTokens(
                lineVariety.tokenMatches[0].assertAs(TokenGrepMethod.Glob).tokens
            );
            if (returnNodes.length != 1)
                throw new SyntaxError("Return statement invalid", returnNodes.data);

            AstNode returnNode = new AstNode;
            returnNode.action = AstAction.ReturnStatement;
            returnNode.nodeToReturn = returnNodes[0];
            parent.instructions ~= returnNode;
            break;
        case LineVariety.IfStatementWithScope:
        case LineVariety.IfStatementWithoutScope:
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;

            size_t temp;

            auto conditionNodes = expressionNodeFromTokens(
                lineVariety.tokenMatches[0].assertAs(TokenGrepMethod.Glob).tokens
            );
            if (conditionNodes.length != 1)
                throw new SyntaxError(
                    "Expression node tree could not be parsed properly (Not reducable into single node within if statement condition)",
                    lineVariety.tokenMatches[0].tokens[0]);

            ConditionNodeData conditionNodeData;
            conditionNodeData.precedingKeywords = keywords;
            conditionNodeData.condition = conditionNodes[0];
            if (lineVariety.lineVariety == LineVariety.IfStatementWithScope) {
                conditionNodeData.isScope = true;
                conditionNodeData.conditionScope
                    = parseMultilineScope(
                        FUNCTION_SCOPE_PARSE,
                        lineVariety.tokenMatches[1].assertAs(TokenGrepMethod.Glob)
                            .tokens,
                            temp,
                            nullable!ScopeData(parent)
                    );
            }
            else {
                conditionNodeData.isScope = false;
                auto conditionLineNode = expressionNodeFromTokens(
                    lineVariety.tokenMatches[1].assertAs(TokenGrepMethod.Glob).tokens
                );
                if (conditionLineNode.length != 1)
                    throw new SyntaxError(
                        "Expression node tree could not be parsed properly (if without scope)",
                        lineVariety.tokenMatches[1].tokens[0]);
                conditionNodeData.conditionResultNode = conditionLineNode[0];

            }
            AstNode node = new AstNode();
            node.action = AstAction.IfStatement;
            node.conditionNodeData = conditionNodeData;
            parent.instructions ~= node;
            break;
        case LineVariety.ElseStatementWithScope:
        case LineVariety.ElseStatementWithoutScope:
            if (!parent.instructions.length || parent.instructions[$ - 1].action != AstAction
                .IfStatement)
                throw new SyntaxError(
                    "Else statement without if statement!",
                    lineVariety.tokenMatches[1].tokens[0]);
            AstNode node = new AstNode();
            node.action = AstAction.ElseStatement;
            size_t endingIndex = index + lineVariety.length;
            scope (exit)
                index = endingIndex;

            ElseNodeData elseNodeData;
            elseNodeData.precedingKeywords = keywords;
            if (lineVariety.lineVariety == LineVariety.ElseStatementWithScope) {
                size_t temp;
                elseNodeData.isScope = true;
                elseNodeData.elseScope
                    = parseMultilineScope(
                        FUNCTION_SCOPE_PARSE,
                        lineVariety.tokenMatches[0].assertAs(TokenGrepMethod.Glob)
                            .tokens,
                            temp,
                            nullable!ScopeData(parent)
                    );
            }
            else {
                elseNodeData.isScope = false;
                auto lineNode = expressionNodeFromTokens(
                    lineVariety.tokenMatches[0].assertAs(TokenGrepMethod.Glob).tokens
                );
                if (lineNode.length != 1)
                    throw new SyntaxError(
                        "Expression node tree could not be parsed properly (else without scope)",
                        lineVariety.tokenMatches[0].tokens[0]);
                elseNodeData.elseResultNode = lineNode[0];
            }
            node.elseNodeData = elseNodeData;
            parent.instructions ~= node;
            break;
        case LineVariety.SimpleExpression:
            size_t expression_end = tokens.findNearestSemiColon(index);
            if (expression_end == -1)
                throw new SyntaxError("Semicolon not found!", tokens[index]);
            auto nodes = expressionNodeFromTokens(tokens[index .. expression_end]);
            nodes.writeln;
            if (nodes.length != 1)
                throw new SyntaxError(
                    "Expression node tree could not be parsed properly (Not reducable into single node in SimpleExpression)", nodes
                        .data);
            parent.instructions ~= nodes[0];
            index = expression_end + 1;

            break;
        default:
            import std.conv;

            assert(0, "Not yet implemented: " ~ lineVariety.lineVariety.to!string);

    }
    return lineVariety;
}

ScopeData parseMultilineScope(const(VarietyTestPair[]) scopeParseMethod, Token[] tokens, ref size_t index, Nullable!ScopeData parent) {
    ScopeData scopeData = new ScopeData;
    scopeData.parent = parent;
    while (index < tokens.length) {
        LineVarietyTestResult lineData = parseLine(scopeParseMethod, tokens, index, scopeData);
        Nullable!Token testToken = tokens.nextNonWhiteToken(index);
        if (testToken == null)
            break;
        index--;

    }

    return scopeData;
}

ScopeData parseMultilineScope(const(VarietyTestPair[]) scopeParseMethod, string data) {
    import fnc.tokenizer.make_tokens;

    size_t index;
    GLOBAL_ERROR_STATE = data;
    return parseMultilineScope(
        scopeParseMethod,
        data.tokenizeText,
        index,
        nullable!ScopeData(null)
    );
}

void argTree(FunctionArgument arg, size_t tabCount, void delegate() printTabs) {
    printTabs();
    arg.name.write;
    if (arg.type != null) {
        writeln(" as type:");
        arg.type.value.tree(tabCount + 1);
    }
    else
        "\n".write;
    if (arg.maybeDefault != null) {
        printTabs();
        writeln("With a default value of: ");
        arg.maybeDefault.value.tree(tabCount + 1);
    }
}

void ftree(DeclaredFunction func, size_t tabCount) {
    alias printTabs() = {
        foreach (_; 0 .. tabCount)
            write("|  ");
    };
    printTabs();
    write(func.precedingKeywords);
    write(" ");
    write(func.returnType);
    write(" ");
    writeln(func.name);
    tabCount++;
    if (func.genericArgs != null) {
        printTabs();
        write("With genric argments(");
        write(func.genericArgs.value.length);
        writeln(")");
        tabCount++;
        foreach (arg; func.genericArgs.value)
            argTree(arg, tabCount, () { printTabs(); });
        tabCount--;
    }

    printTabs();
    write("With argments(");
    write(func.args.length);
    writeln(")");
    tabCount++;
    foreach (arg; func.args)
        argTree(arg, tabCount, () { printTabs(); });
    if (func.functionScope != null) {
        func.functionScope.value.tree(--tabCount);
    }
    else {
        tabCount--;
        printTabs();
        writeln("Is abstract function: true");
    }
}

void tree(ScopeData scopeData) => tree(scopeData, 0);
void tree(ScopeData scopeData, size_t tabCount) {
    import std.conv;

    alias printTabs() = {
        foreach (_; 0 .. tabCount)
            write("|  ");
    };
    alias printTabsV() = { printTabs(); write("┼ "); };

    printTabsV();
    write("Scope:");
    if (scopeData.moduleName != null){
        write(" Name = ");
        write(scopeData.moduleName.value.to!string);

    }
    write(" isPartialModule = ");
    writeln(scopeData.isPartialModule);
    tabCount++;

    printTabs();
    write("Variables: ");
    foreach (var; scopeData.declaredVariables) {
        write(var.name.to!string ~ " as " ~ var.type.to!string);
        write(", ");
    }
    write("\n");
    printTabs();
    write("Imports: ");
    foreach (imported; scopeData.imports) {
        write(imported.namedUnit);
        write(": (");
        foreach (selection; imported.importSelection) {
            selection.write;
            write(", ");
        }
        write("), ");
    }
    write("\n");
    printTabs();
    writeln("Functions: ");
    tabCount++;
    foreach (func; scopeData.declaredFunctions) {
        func.ftree(tabCount);
    }

    tabCount--;
    printTabs();
    writeln("Objects: ");
    tabCount++;

    foreach (obj; scopeData.declaredObjects) {
        printTabs();
        obj.type.write;
        "\t".write;
        obj.name.write;
        ":".writeln;
        tabCount++;
        if (obj.genericArgs != null) {
            printTabs();
            write("With genric argments(");
            write(obj.genericArgs.value.length);
            writeln(")");
            tabCount++;
            foreach (arg; obj.genericArgs.value)
                argTree(arg, tabCount, () { printTabs(); });
            tabCount--;
        }

        foreach (var; obj.declaredVariables) {
            printTabs();
            var.type.write;
            "\t".write;
            var.name.writeln;
        }
        tabCount--;
        printTabs();
        writeln("Functions:");
        tabCount++;
        foreach (func; obj.declaredFunctions) {
            func.ftree(tabCount + 1);
        }
        tabCount--;

    }
    tabCount--;
    printTabs();
    writeln("AST nodes(" ~ scopeData.instructions.length.to!string ~ "):");
    foreach (AstNode node; scopeData.instructions) {
        node.tree(tabCount);
    }

}
