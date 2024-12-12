require('module-alias/register');
const eventRoutes = require('@middleware/events/eventRoutes');
const { genTblHeader, genHeader, genTable } = require("wf-jspdf");
const fs = require('fs');

// Initial setup for the PDF document
const orientation = 'p';
const docName = 'Whatsfresh API Virtual Endpoints'
const title = 'Whatsfresh: ';
const name = 'Events';
const descr = "The list of API Events driving the Whatsfresh processing";
let result = genHeader(orientation, 'Whatsfresh API Endpoints', title, name, descr);

// Define the methods and their descriptions
const methodsDescriptions = [
  { Method: 'GET', Description: 'Retrieves data for the selected Entity.' },
  { Method: 'POST', Description: 'Creates a new row for the specified table.' },
  { Method: 'PUT', Description: 'Updates the selected row with new data.' },
  { Method: 'DELETE', Description: 'Deletes the selected row.' },
  { Method: 'SDELETE', Description: 'SOFT DELETE: Updates the deleted_at column with NOW() to indicate the row is no longer active.' }
];

// Define column styles for the methods table
const methodsColumnStyles = {
  0: { cellWidth: 80, halign: 'center', fontStyle: 'bold', fillColor: '#ffffe6' },
  1: { cellWidth: 400, halign: 'left' }
};

// Add the methods table to the document
result = genTable(result.doc, methodsDescriptions, methodsColumnStyles, result.finalY);

// Adjust finalY after adding the methods table
result.finalY += methodsDescriptions.length * 3; // Adjust based on the number of rows and extra space

// Column styles definition for the main table
const columnStyles = { 
  0: { cellWidth: 90, halign: 'center', fontStyle: 'bold', fillColor: '#ffffe6' },
  1: { cellWidth: 80, halign: 'center', fontStyle: 'bold' },
  2: { cellWidth: 100, halign: 'center' },
  3: { cellWidth: 80, halign: 'center' },
  4: { cellWidth: 200, halign: 'left' },
};

// Function to estimate the height of the qrySQL text by counting newline characters
function estimateHeight(text) {
  if (!text) return 12; // Return default height for null or undefined text
  const numNewlines = (text.match(/\n/g) || []).length;
  return (numNewlines + 1) * 3; // Adjust height calculation, 16px line height for 12pt font
}

// Create a set of unique paths (minus the file)
const uniquePaths = new Set(eventRoutes.map(route => route.path));

console.log('Unique Paths:', Array.from(uniquePaths));

// Loop through each unique path and generate the document
uniquePaths.forEach(path => {
  console.log('Processing path:', path);

  // Generate a table header for each unique path
  result = genTblHeader(result.doc, path, result.finalY);

  // Extract the data for the current path
  const tableData = eventRoutes
    .filter(route => route.path)
    .map(route => ({
      'Event Type': route.eventType,
      'Method': route.method,
      'Params': route.params,
      'BodyCols': route.bodyCols,
      'QrySQL': route.qrySQL
    }));

  // Log table data for debugging

  // Generate a single table for the group with transformed data
  result = genTable(result.doc, tableData, columnStyles, result.finalY);

  // Estimate total height required for the qrySQL column after generating the table
  let tableHeight = 0;
  tableData.forEach(row => {
    tableHeight += estimateHeight(row['QrySQL']);
  });

  // Adjust finalY for the next header and table
  result.finalY += tableHeight + 3; // Add extra space to ensure proper spacing
});

// Convert the PDF output to data URL string
const pdfOutput = result.doc.output('dataurlstring');

// Extract the PDF data and save to a file
const pdfData = pdfOutput.split(',')[1]; // Remove the data URL prefix
const pdfBuffer = Buffer.from(pdfData, 'base64');
const pdfPath = 'C:/Users/pc790/OneDrive/Consulting/Whatsfresh/aaEventRoutes.pdf';
fs.writeFileSync(pdfPath, pdfBuffer);

console.log('PDF saved successfully to', pdfPath);
