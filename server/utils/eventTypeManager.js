const fs = require('fs').promises;
const path = require('path');
const logger = require('./logger');
const codeName = '[eventTypeManager.js]';

// In-memory cache
let eventTypesCache = null;
let lastRefreshTime = null;

class EventTypeManager {
    constructor() {
        this.eventTypesPath = path.join(__dirname, '../middleware/eventTypes.js');
    }

    /**
     * Get event types from cache or file
     * @returns {Promise<Array>} Array of event types
     */
    async getEventTypes() {
        if (eventTypesCache) {
            return eventTypesCache;
        }
        return this.refreshEventTypes();
    }

    /**
     * Force refresh event types from file
     * @returns {Promise<Array>} Fresh array of event types
     */
    async refreshEventTypes() {
        try {
            // Clear require cache to ensure fresh read
            delete require.cache[require.resolve('../middleware/eventTypes')];
            
            // Load from file
            eventTypesCache = require('../middleware/eventTypes');
            lastRefreshTime = new Date();
            
            logger.info(`${codeName} Event types refreshed at ${lastRefreshTime}`);
            return eventTypesCache;
        } catch (error) {
            logger.error(`${codeName} Error refreshing event types:`, error);
            throw error;
        }
    }

    /**
     * Update event types file and cache
     * @param {Array} newEventTypes - New array of event types
     */
    async updateEventTypes(newEventTypes) {
        try {
            // Format the file content
            const fileContent = `module.exports = ${JSON.stringify(newEventTypes, null, 2)};`;
            
            // Write to file
            await fs.writeFile(this.eventTypesPath, fileContent, 'utf8');
            
            // Update cache
            eventTypesCache = newEventTypes;
            lastRefreshTime = new Date();
            
            logger.info(`${codeName} Event types updated at ${lastRefreshTime}`);
        } catch (error) {
            logger.error(`${codeName} Error updating event types:`, error);
            throw error;
        }
    }

    /**
     * Get cache status
     * @returns {Object} Cache status information
     */
    getCacheStatus() {
        return {
            isCached: !!eventTypesCache,
            lastRefreshTime,
            eventCount: eventTypesCache ? eventTypesCache.length : 0
        };
    }

    /**
     * Find an event type by its type name
     * @param {string} eventType - The event type to find
     * @returns {Object|null} The found event type or null
     */
    async findEventType(eventType) {
        const types = await this.getEventTypes();
        return types.find(et => et.eventType === eventType) || null;
    }
}

// Export singleton instance
module.exports = new EventTypeManager(); 
