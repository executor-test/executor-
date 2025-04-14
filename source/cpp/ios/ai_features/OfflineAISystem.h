#pragma once

#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <unordered_map>

namespace iOS {
namespace AIFeatures {

/**
 * @class OfflineAISystem
 * @brief Fully offline AI system with no external dependencies
 * 
 * This class provides a completely self-contained AI system that works entirely
 * offline with local models. It handles model loading, memory management, and
 * coordination between AI components with no external service connections.
 */
class OfflineAISystem {
public:
    // AI request structure
    struct AIRequest {
        std::string m_query;         // User query
        std::string m_context;       // Additional context (e.g., script content)
        std::string m_requestType;   // Request type (e.g., "script_generation", "debug")
        uint64_t m_timestamp;        // Request timestamp
        
        AIRequest() : m_timestamp(0) {}
        
        AIRequest(const std::string& query, 
                 const std::string& context = "", 
                 const std::string& requestType = "general")
            : m_query(query), m_context(context), m_requestType(requestType),
              m_timestamp(std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count()) {}
    };
    
    // AI response structure
    struct AIResponse {
        bool m_success;              // Success flag
        std::string m_content;       // Response content
        std::string m_scriptCode;    // Generated script code (if applicable)
        std::vector<std::string> m_suggestions; // Suggested actions
        uint64_t m_processingTime;   // Processing time in milliseconds
        std::string m_errorMessage;  // Error message if failed
        
        AIResponse() : m_success(false), m_processingTime(0) {}
        
        AIResponse(bool success, const std::string& content = "", 
                  const std::string& scriptCode = "", uint64_t processingTime = 0,
                  const std::string& errorMessage = "")
            : m_success(success), m_content(content), m_scriptCode(scriptCode),
              m_processingTime(processingTime), m_errorMessage(errorMessage) {}
    };
    
    // Callback for AI responses
    using ResponseCallback = std::function<void(const AIResponse&)>;
    
private:
    // Member variables with consistent m_ prefix
    bool m_initialized;                       // Initialization flag
    bool m_modelsLoaded;                      // Models loaded flag
    bool m_isInLowMemoryMode;                 // Low memory mode flag
    void* m_scriptAssistantModel;             // Opaque pointer to script assistant model
    void* m_scriptGeneratorModel;             // Opaque pointer to script generator model
    void* m_debugAnalyzerModel;               // Opaque pointer to debug analyzer model
    void* m_patternRecognitionModel;          // Opaque pointer to pattern recognition model
    std::unordered_map<std::string, void*> m_modelCache; // Model cache
    std::string m_modelPath;                  // Path to model files
    std::vector<std::string> m_loadedModelNames; // Names of loaded models
    std::vector<AIRequest> m_requestHistory;  // Request history for learning
    std::vector<AIResponse> m_responseHistory; // Response history for learning
    std::unordered_map<std::string, std::string> m_templateCache; // Script template cache
    uint64_t m_totalMemoryUsage;              // Total memory usage in bytes
    uint64_t m_maxMemoryAllowed;              // Maximum allowed memory in bytes
    ResponseCallback m_responseCallback;      // Response callback
    std::mutex m_mutex;                       // Mutex for thread safety
    
    // Private methods
    bool LoadModel(const std::string& modelName, int priority);
    void UnloadModel(const std::string& modelName);
    void OptimizeMemoryUsage();
    bool IsModelLoaded(const std::string& modelName) const;
    void* GetModel(const std::string& modelName) const;
    AIResponse ProcessScriptGeneration(const AIRequest& request);
    AIResponse ProcessScriptDebugging(const AIRequest& request);
    AIResponse ProcessGeneralQuery(const AIRequest& request);
    std::string GenerateScriptFromTemplate(const std::string& templateName, 
                                         const std::unordered_map<std::string, std::string>& parameters);
    std::vector<std::string> ExtractCodeBlocks(const std::string& text);
    std::vector<std::string> ExtractIntents(const std::string& query);
    uint64_t CalculateModelMemoryUsage(void* model) const;
    
public:
    /**
     * @brief Constructor
     */
    OfflineAISystem();
    
    /**
     * @brief Destructor
     */
    ~OfflineAISystem();
    
    /**
     * @brief Initialize the AI system
     * @param modelPath Path to model files
     * @param progressCallback Function to call with initialization progress (0.0-1.0)
     * @return True if initialization succeeded, false otherwise
     */
    bool Initialize(const std::string& modelPath, std::function<void(float)> progressCallback = nullptr);
    
    /**
     * @brief Process an AI request
     * @param request AI request
     * @param callback Function to call with the response
     */
    void ProcessRequest(const AIRequest& request, ResponseCallback callback);
    
    /**
     * @brief Process an AI request synchronously
     * @param request AI request
     * @return AI response
     */
    AIResponse ProcessRequestSync(const AIRequest& request);
    
    /**
     * @brief Generate a script
     * @param description Script description
     * @param context Additional context (e.g., game type)
     * @param callback Function to call with the generated script
     */
    void GenerateScript(const std::string& description, const std::string& context, 
                       std::function<void(const std::string&)> callback);
    
    /**
     * @brief Debug a script
     * @param script Script to debug
     * @param callback Function to call with debug information
     */
    void DebugScript(const std::string& script, 
                    std::function<void(const std::string&)> callback);
    
    /**
     * @brief Process a general query
     * @param query User query
     * @param callback Function to call with the response
     */
    void ProcessQuery(const std::string& query, 
                     std::function<void(const std::string&)> callback);
    
    /**
     * @brief Handle memory warning
     */
    void HandleMemoryWarning();
    
    /**
     * @brief Check if the AI system is initialized
     * @return True if initialized, false otherwise
     */
    bool IsInitialized() const;
    
    /**
     * @brief Check if models are loaded
     * @return True if loaded, false otherwise
     */
    bool AreModelsLoaded() const;
    
    /**
     * @brief Get memory usage
     * @return Memory usage in bytes
     */
    uint64_t GetMemoryUsage() const;
    
    /**
     * @brief Set maximum allowed memory
     * @param maxMemory Maximum allowed memory in bytes
     */
    void SetMaxMemory(uint64_t maxMemory);
    
    /**
     * @brief Get loaded model names
     * @return Vector of loaded model names
     */
    std::vector<std::string> GetLoadedModelNames() const;
    
    /**
     * @brief Get a list of script templates
     * @return Map of template names to descriptions
     */
    std::unordered_map<std::string, std::string> GetScriptTemplates() const;
    
    /**
     * @brief Get template cache
     * @return Map of template names to templates
     */
    std::unordered_map<std::string, std::string> GetTemplateCache() const;
    
    /**
     * @brief Generate response for a detection event
     * @param detectionType Detection type
     * @param signature Detection signature
     * @return Protection strategy
     */
    std::string GenerateProtectionStrategy(const std::string& detectionType, 
                                         const std::vector<uint8_t>& signature);
};

} // namespace AIFeatures
} // namespace iOS
