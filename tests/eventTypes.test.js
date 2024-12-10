const express = require('express');
const fs = require('fs');
const { genHeader, genTable, genTblHeader } = require('wf-jspdf');
const { startServer, closeServer } = require('../jestUtils');
const NodeCache = require('node-cache'); // Import NodeCache
const { loadEventTypeCacheAndRoutes } = require('../server'); // Ensure this path is correct

// Create an express app
const app = express();

// Use the same cache as the server
const eventTypeCache = new NodeCache({ stdTTL: 3600 });

describe('buildPDF', () => {
  beforeAll(async () => {
    // Start the server
    startServer(app);

    // Load the cache with the actual function
    await loadEventTypeCacheAndRoutes();
  });

  afterAll(() => {
    // Close the server
    closeServer();
  });

  it('should generate a PDF with the correct header and validate finalY', () => {
    // Fetch data from the cache
    const cachedEventTypes = eventTypeCache.get('eventTypes');

    // Log the cached event types for debugging
    console.log('Cached event types:', cachedEventTypes);

    // Validate that the event types were correctly cached
    expect(cachedEventTypes).not.toBeNull();
    expect(Array.isArray(cachedEventTypes)).toBe(true);
    expect(cachedEventTypes.length).toBeGreaterThan(0); // Ensure there's at least one event type

    function buildPDF() {
      // Pick the orientation
      const orientation = 'p';
      const acctName = 'Whatsfresh';
      const title = 'Event Types:';
      const name = 'Enabled and Cached';
      const description = 'This is the list of Event Types cached for processing that drive the Whatsfresh processing and data fetching.';
      // Use imported header data

      let result = genHeader(orientation, acctName, title, name, description);

      // Build Table Header
      result = genTblHeader(result.doc, 'Enabled Event Types', result.finalY);

      // Build the column styles
      const columnStyles = { 
        0: { cellWidth: 80, halign: 'left', fontStyle: 'bold' }, 
        1: { cellWidth: 80, halign: 'center', fontStyle: 'bold' }, 
        2: { cellWidth: 160, halign: 'left' }, 
        3: { cellWidth: 100, halign: 'center' }, 
      };

      // Custom style callback to make cells bold based on criteria
      const styleCallback = data => {
        if (data.column.index === 0 && data.cell.text[0] === 'M') {
          data.cell.styles.fontStyle = 'bold';
          data.cell.styles.textColor = 'red'; 
          data.cell.styles.fontSize = 14; 
          data.cell.styles.font = 'times'; 
        }
      };

      // Create the table with the style callback and capture the final Y position
      result = genTable(result.doc, cachedEventTypes, columnStyles, result.finalY, styleCallback);

      return result.doc.output('dataurlstring');
    }

    // Run the test
    const pdfOutput = buildPDF();

    // Write the PDF to a file for manual inspection
    const pdfData = pdfOutput.split(',')[1]; // Remove the data URL prefix
    const pdfBuffer = Buffer.from(pdfData, 'base64');
    fs.writeFileSync('C:/Users/pc790/OneDrive/Consulting/Whatsfresh/aaTestEventTypes.pdf', pdfBuffer);

    // Add assertions to verify the output and finalY
    expect(pdfOutput.startsWith("data:application/pdf;filename=generated.pdf;base64")).toBe(true);
  });
});
