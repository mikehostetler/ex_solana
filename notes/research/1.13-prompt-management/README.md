# Jido Prompt Ontology

An RDF/OWL ontology module for representing, categorizing, and versioning LLM prompts within the JidoCode ecosystem. Fully integrated with the existing Jido ontology family.

## Integration with Jido Ontologies

This ontology integrates with the existing Jido ontology ecosystem:

```
jido-core.ttl (Foundation)
    │
    ├── jido-agent.ttl         ─┐
    ├── jido-knowledge.ttl      │
    ├── jido-project.ttl        ├── jido-prompt.ttl imports these
    └── jido-session.ttl       ─┘
            │
            └── jido-prompt.ttl (This module)
                    │
                    ├── jido-prompt-taxonomy.ttl (Categories)
                    ├── jido-prompt-shacl.ttl (Validation)
                    └── jido-prompt-examples.ttl (Instances)
```

## Files

| File | Description |
|------|-------------|
| `jido-prompt.ttl` | Core prompt ontology classes and properties |
| `jido-prompt-taxonomy.ttl` | SKOS-based multi-level category taxonomy |
| `jido-prompt-shacl.ttl` | SHACL validation shapes for CI |
| `jido-prompt-examples.ttl` | Example prompt instances |

## Namespace

All classes and properties use the standard Jido namespace:

```turtle
@base <https://jido.ai/ontology#> .
@prefix jido: <https://jido.ai/ontology#> .
```

## Core Design

### Prompt as MemoryItem

`jido:Prompt` is a subclass of `jido:MemoryItem`, inheriting provenance properties:

```turtle
jido:Prompt rdfs:subClassOf jido:MemoryItem .

# Prompts inherit these from MemoryItem:
# - jido:assertedBy → jido:Agent
# - jido:assertedIn → jido:WorkSession
# - jido:appliesToProject → jido:Project
# - jido:hasConfidence → jido:ConfidenceLevel
# - jido:hasTimestamp → xsd:dateTime
# - jido:supersededBy → jido:MemoryItem
```

### Prompt Type Hierarchy

```
jido:Prompt
├── jido:SystemPrompt         # System-level context
├── jido:UserPrompt           # User interaction templates
├── jido:AssistantPrompt      # Response templates
├── jido:MetaPrompt           # Prompts that generate prompts
├── jido:PromptFragment       # Reusable partial prompts
├── jido:ToolPrompt           # Tool/function definitions
└── jido:ValidationPrompt     # Output validation prompts
```

### Category Dimensions

Multi-dimensional classification using SKOS:

| Dimension | Class | Examples |
|-----------|-------|----------|
| Domain | `jido:DomainCategory` | Coding, Elixir, Phoenix, Ash |
| Task | `jido:TaskCategory` | Generation, Evaluation, Extraction |
| Technique | `jido:TechniqueCategory` | Chain-of-Thought, Few-Shot, ReAct |
| Complexity | `jido:ComplexityCategory` | Simple, Intermediate, Advanced |
| Audience | `jido:AudienceCategory` | Beginner, Developer, Expert |

### Status Lifecycle

```
jido:PromptDraft → jido:PromptReview → jido:PromptPublished
                                              ↓
                                    jido:PromptDeprecated
                                              ↓
                                    jido:PromptArchived
```

## Usage Examples

### Creating a Prompt

```turtle
@prefix jido: <https://jido.ai/ontology#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

:my-review-prompt a jido:SystemPrompt ;
    # Identity
    jido:promptId "my-review-001" ;
    jido:promptName "My Code Review Prompt" ;
    jido:promptDescription "Reviews code for quality." ;
    
    # Content (markdown)
    jido:hasPromptContent [
        a jido:PromptContent ;
        jido:hasContentFormat jido:MarkdownFormat ;
        jido:contentText """# Review the following code:
        
        {{code}}
        
        Provide feedback on quality and style.
        """
    ] ;
    
    # Variables
    jido:hasVariable [
        a jido:PromptVariable ;
        jido:variableName "code" ;
        jido:variableType "string" ;
        jido:variableRequired true
    ] ;
    
    # Categories (multi-level)
    jido:hasDomainCategory jido:CodeReviewDomain ;
    jido:hasTaskCategory jido:EvaluationTask ;
    jido:hasTechniqueCategory jido:ZeroShotTechnique ;
    jido:hasComplexityCategory jido:IntermediateComplexity ;
    
    # Provenance (inherited from MemoryItem)
    jido:assertedBy :my-agent ;
    jido:hasConfidence jido:High ;
    jido:hasTimestamp "2024-12-29T10:00:00Z"^^xsd:dateTime ;
    jido:appliesToProject :my-project ;
    
    # Version
    jido:currentPromptVersion [
        a jido:PromptVersion ;
        jido:versionNumber "1.0.0" ;
        jido:hasPromptStatus jido:PromptPublished ;
        jido:versionOf :my-review-prompt
    ] ;
    
    # Agent integration
    jido:usedByAgent :my-coding-agent ;
    
    # Tags
    jido:hasPromptTag "review", "quality" .
```

### Composing Prompts from Fragments

```turtle
:composed-prompt a jido:SystemPrompt ;
    jido:promptId "composed-001" ;
    jido:promptName "Composed Prompt" ;
    
    # Include fragments
    jido:composedOfFragment :intro-fragment, :rules-fragment, :output-fragment ;
    
    # Fragments have positions
    jido:hasPromptContent [
        jido:contentText "Composed content here..."
    ] .

:intro-fragment a jido:PromptFragment ;
    jido:fragmentPosition 1 ;
    jido:hasPromptContent [...] .

:rules-fragment a jido:PromptFragment ;
    jido:fragmentPosition 2 ;
    jido:hasPromptContent [...] .
```

### Version Chain with Deprecation

```turtle
:my-prompt jido:hasPromptVersion :v1, :v2, :v3 ;
           jido:currentPromptVersion :v3 .

:v1 jido:versionNumber "1.0.0" ;
    jido:hasPromptStatus jido:PromptDeprecated ;
    jido:versionOf :my-prompt .

:v2 jido:versionNumber "1.1.0" ;
    jido:previousPromptVersion :v1 ;
    jido:hasPromptStatus jido:PromptDeprecated ;
    jido:versionOf :my-prompt .

:v3 jido:versionNumber "2.0.0" ;
    jido:previousPromptVersion :v2 ;
    jido:hasPromptStatus jido:PromptPublished ;
    jido:versionOf :my-prompt .
```

## SPARQL Queries

### Find prompts by category hierarchy

```sparql
PREFIX jido: <https://jido.ai/ontology#>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

SELECT ?prompt ?name ?category
WHERE {
    ?prompt a jido:Prompt ;
            jido:promptName ?name ;
            jido:hasDomainCategory ?category .
    ?category skos:broader* jido:ElixirDevelopmentDomain .
}
```

### Find prompts by agent

```sparql
PREFIX jido: <https://jido.ai/ontology#>

SELECT ?prompt ?promptName ?agentName
WHERE {
    ?prompt jido:usedByAgent ?agent ;
            jido:promptName ?promptName .
    ?agent jido:agentName ?agentName .
}
```

### Find version history

```sparql
PREFIX jido: <https://jido.ai/ontology#>

SELECT ?version ?number ?status
WHERE {
    ?version jido:versionOf :my-prompt ;
             jido:versionNumber ?number ;
             jido:hasPromptStatus ?status .
}
ORDER BY ?number
```

### Find prompts with specific technique

```sparql
PREFIX jido: <https://jido.ai/ontology#>

SELECT ?prompt ?name
WHERE {
    ?prompt jido:promptName ?name ;
            jido:hasTechniqueCategory jido:ChainOfThoughtTechnique .
}
```

## SHACL Validation

Key validation rules enforced:

1. **PromptIdentityShape**: Every prompt must have unique ID and name
2. **PromptContentRequiredShape**: Every prompt must have content
3. **PromptProvenanceShape**: Prompts inherit MemoryItem provenance requirements
4. **PromptVersionShape**: Versions must follow semver format
5. **PublishedPromptCategoryShape**: Published prompts must have categories
6. **PromptVariableShape**: Variables must have valid identifier names
7. **NoCyclicVersionShape**: Version chains cannot contain cycles
8. **DeprecatedPromptReplacementShape**: Deprecated prompts should have replacements

### Running Validation

```python
from rdflib import Graph
from pyshacl import validate

# Load data
data = Graph()
data.parse("jido-prompt-examples.ttl", format="turtle")

# Load shapes
shapes = Graph()
shapes.parse("jido-prompt-shacl.ttl", format="turtle")

# Validate
conforms, results_graph, results_text = validate(
    data,
    shacl_graph=shapes,
    inference='rdfs'
)

if not conforms:
    print(results_text)
```

## File Organization

Recommended placement in your project:

```
lib/ontology/
├── long-term-context/
│   ├── jido-core.ttl
│   ├── jido-agent.ttl
│   ├── jido-knowledge.ttl
│   ├── jido-project.ttl
│   ├── jido-session.ttl
│   ├── jido-task.ttl
│   ├── jido-decision.ttl
│   ├── jido-convention.ttl
│   ├── jido-error.ttl
│   ├── jido-code.ttl
│   ├── jido-ci-shacl.ttl
│   │
│   ├── jido-prompt.ttl          # ← New
│   ├── jido-prompt-taxonomy.ttl # ← New
│   └── jido-prompt-shacl.ttl    # ← New
│
├── prompts/
│   └── jido-prompt-examples.ttl # ← Instance data
│
└── security/
    └── elixir-security-shapes.ttl
```

## Key Integration Points

### With jido-agent.ttl

```turtle
# Link prompts to agents
jido:promptCreatedBy rdfs:subPropertyOf jido:assertedBy .
jido:usedByAgent rdfs:range jido:Agent .
jido:definesAgentBehavior rdfs:range jido:Agent .
```

### With jido-project.ttl

```turtle
# Prompts belong to projects (via MemoryItem)
jido:appliesToProject rdfs:domain jido:MemoryItem .
jido:appliesToProject rdfs:range jido:Project .
```

### With jido-session.ttl

```turtle
# Track when prompts were created/used
jido:assertedIn rdfs:range jido:WorkSession .
```

### With jido-convention.ttl

```turtle
# Prompt guidelines can be modeled as conventions
:PromptStyleGuide a jido:CodingStandard ;
    jido:conventionDescription "Guidelines for writing prompts" ;
    jido:hasEnforcementLevel jido:Required .
```

## License

MIT License - Consistent with the Jido ontology family.

