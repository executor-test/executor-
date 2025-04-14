#include "MemoryAccess.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <dlfcn.h>
#include <mach/mach_error.h>
#include <mach-o/dyld_images.h>
#include <sys/sysctl.h>

namespace iOS {
    // Initialize static members
    mach_port_t MemoryAccess::m_targetTask = MACH_PORT_NULL;
    bool MemoryAccess::m_initialized = false;
    
    bool MemoryAccess::Initialize() {
        // If already initialized, return success
        if (m_initialized) {
            return true;
        }
        
        // Get the task port for our own process (Roblox)
        kern_return_t kr = task_self_trap();
        if (kr == KERN_SUCCESS) {
            m_targetTask = kr;
            m_initialized = true;
            return true;
        }
        
        std::cerr << "Failed to get task port: " << mach_error_string(kr) << std::endl;
        return false;
    }
    
    bool MemoryAccess::ReadMemory(mach_vm_address_t address, void* buffer, size_t size) {
        if (!m_initialized) {
            return false;
        }
        
        vm_size_t bytesRead;
        kern_return_t kr = vm_read_overwrite(m_targetTask, address, size, 
                                           (vm_address_t)buffer, &bytesRead);
        
        if (kr != KERN_SUCCESS) {
            std::cerr << "ReadMemory failed: " << mach_error_string(kr) << std::endl;
            return false;
        }
        
        return bytesRead == size;
    }
    
    bool MemoryAccess::WriteMemory(mach_vm_address_t address, const void* buffer, size_t size) {
        if (!m_initialized) {
            return false;
        }
        
        kern_return_t kr = vm_write(m_targetTask, address, (vm_offset_t)buffer, size);
        
        if (kr != KERN_SUCCESS) {
            std::cerr << "WriteMemory failed: " << mach_error_string(kr) << std::endl;
            return false;
        }
        
        return true;
    }
    
    bool MemoryAccess::ProtectMemory(mach_vm_address_t address, size_t size, vm_prot_t protection) {
        if (!m_initialized) {
            return false;
        }
        
        kern_return_t kr = vm_protect(m_targetTask, address, size, FALSE, protection);
        
        if (kr != KERN_SUCCESS) {
            std::cerr << "ProtectMemory failed: " << mach_error_string(kr) << std::endl;
            return false;
        }
        
        return true;
    }
    
    bool MemoryAccess::GetMemoryRegions(std::vector<vm_region_basic_info_data_64_t>& regions) {
        if (!m_initialized) {
            return false;
        }
        
        regions.clear();
        
        // Variables for memory region iteration
        vm_address_t vm_address = 0; // Use vm_address_t for compatibility with vm_region_64
        vm_size_t vm_size = 0; // Use vm_size_t for compatibility with vm_region_64
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName = MACH_PORT_NULL;
        kern_return_t kr = KERN_SUCCESS;
        
        while (true) {
            // Use variables with correct types for vm_region_64
            kr = vm_region_64(
                m_targetTask,
                &vm_address,
                &vm_size,
                VM_REGION_BASIC_INFO_64,
                (vm_region_info_t)&info, 
                &infoCount, 
                &objectName);
            
            if (kr != KERN_SUCCESS) {
                if (kr != KERN_INVALID_ADDRESS) {
                    std::cerr << "GetMemoryRegions failed: " << mach_error_string(kr) << std::endl;
                }
                break;
            }
            
            // Store region size in the upper bits of the protection field so we can access it later
            info.protection |= ((uint64_t)vm_size & 0xFFFFFFFF) << 32;
            
            regions.push_back(info);
            vm_address += vm_size;
        }
        
        return !regions.empty();
    }
    
    mach_vm_address_t MemoryAccess::GetModuleBase(const std::string& moduleName) {
        // Get the image count
        const uint32_t imageCount = _dyld_image_count();
        
        // Iterate through all loaded modules
        for (uint32_t i = 0; i < imageCount; i++) {
            const char* imageName = _dyld_get_image_name(i);
            if (imageName && strstr(imageName, moduleName.c_str())) {
                return _dyld_get_image_vmaddr_slide(i) + (mach_vm_address_t)_dyld_get_image_header(i);
            }
        }
        
        return 0;
    }
    
    size_t MemoryAccess::GetModuleSize(mach_vm_address_t moduleBase) {
        if (moduleBase == 0) {
            return 0;
        }
        
        // Read the Mach-O header
        struct mach_header_64 header;
        if (!ReadMemory(moduleBase, &header, sizeof(header))) {
            return 0;
        }
        
        // Ensure it's a valid 64-bit Mach-O
        if (header.magic != MH_MAGIC_64) {
            return 0;
        }
        
        // Calculate the total size from Mach-O segments
        size_t totalSize = 0;
        mach_vm_address_t currentOffset = moduleBase + sizeof(header);
        
        // Skip command headers and calculate size
        for (uint32_t i = 0; i < header.ncmds; i++) {
            struct load_command cmd;
            if (!ReadMemory(currentOffset, &cmd, sizeof(cmd))) {
                break;
            }
            
            if (cmd.cmd == LC_SEGMENT_64) {
                struct segment_command_64 segCmd;
                if (ReadMemory(currentOffset, &segCmd, sizeof(segCmd))) {
                    totalSize += segCmd.vmsize;
                }
            }
            
            currentOffset += cmd.cmdsize;
        }
        
        return totalSize;
    }
    
    mach_vm_address_t MemoryAccess::FindPattern(mach_vm_address_t rangeStart, size_t rangeSize, 
                                              const std::string& pattern, const std::string& mask) {
        // Validate inputs
        if (rangeStart == 0 || rangeSize == 0 || pattern.empty() || mask.empty() || pattern.size() != mask.size()) {
            return 0;
        }
        
        // Allocate buffer for the memory region
        std::vector<uint8_t> buffer(rangeSize);
        
        // Read the memory region
        if (!ReadMemory(rangeStart, buffer.data(), rangeSize)) {
            return 0;
        }
        
        // Convert pattern string to bytes
        std::vector<uint8_t> patternBytes;
        std::istringstream patternStream(pattern);
        std::string byteStr;
        
        while (std::getline(patternStream, byteStr, ' ')) {
            if (byteStr.length() == 2) {
                patternBytes.push_back(static_cast<uint8_t>(std::stoi(byteStr, nullptr, 16)));
            } else {
                patternBytes.push_back(0);
            }
        }
        
        // Search for the pattern
        for (size_t i = 0; i <= buffer.size() - patternBytes.size(); i++) {
            bool found = true;
            
            for (size_t j = 0; j < patternBytes.size(); j++) {
                if (mask[j] != '?' && buffer[i + j] != patternBytes[j]) {
                    found = false;
                    break;
                }
            }
            
            if (found) {
                return rangeStart + i;
            }
        }
        
        return 0;
    }
    
    mach_vm_address_t MemoryAccess::ScanForPattern(const std::string& pattern, const std::string& mask) {
        // Get memory regions
        std::vector<vm_region_basic_info_data_64_t> regions;
        if (!GetMemoryRegions(regions)) {
            return 0;
        }
        
        // Scan each readable region
        mach_vm_address_t address = 0;
        for (const auto& region : regions) {
            // Skip regions that are not readable
            if (!(region.protection & VM_PROT_READ)) {
                continue;
            }
            
            // Extract region size from the upper bits of protection where we stored it
            mach_vm_size_t regionSize = (region.protection >> 32) & 0xFFFFFFFF;
            
            // Use a reasonable default if size wasn't properly stored
            if (regionSize == 0) {
                #if defined(IOS_TARGET) || defined(__APPLE__)
                // For iOS, use a reasonable default scan size
                regionSize = 4 * 1024 * 1024; // 4MB default scan size
                #else
                regionSize = region.virtual_size;
                #endif
            }
            
            // Scan this region with the correct size
            mach_vm_address_t result = FindPattern(address, regionSize, pattern, mask);
            if (result != 0) {
                return result;
            }
            
            // Move to next region using the extracted size
            address += regionSize;
        }
        
        return 0;
    }
    
    void MemoryAccess::Cleanup() {
        if (m_initialized && m_targetTask != MACH_PORT_NULL) {
            m_targetTask = MACH_PORT_NULL;
            m_initialized = false;
        }
    }
}
