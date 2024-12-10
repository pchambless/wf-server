const axios = require('axios');
const PDFDocument = require('pdfkit');
const fs = require('fs');

// Function to fetch the list-routes dataset
async function fetchRoutesData() {
  const response = await axios.get('http://localhost:3001/api/list-routes');
  return response.data.routes;
}

// Function to generate PDF
async function generatePDF() {
  const routes = await fetchRoutesData();

  // Create a new PDF document
  const doc = new PDFDocument();
  doc.pipe(fs.createWriteStream('C:/Users/pc790/OneDrive/Consulting/Whatsfresh/aaEventTypes.pdf'));

  // Add title
  doc.fontSize(20).text('Routes Report', { align: 'center' }).moveDown(2);

  routes.forEach((route, index) => {
    doc.fontSize(12).text(`Route ${index + 1}:`).moveDown(0.5);
    doc.fontSize(10).text(`Path: ${route.path}`).moveDown(0.5);
    doc.fontSize(10).text(`Method: ${route.method}`).moveDown(0.5);
    doc.fontSize(10).text(`Event Type: ${route.eventType}`).moveDown(0.5);
    doc.fontSize(10).text(`Params: ${route.params || 'N/A'}`).moveDown(0.5);
    doc.fontSize(10).text(`BodyCols: ${route.bodyCols || 'N/A'}`).moveDown(0.5);
    doc.fontSize(10).text(`Query SQL: ${route.qrySQL || 'N/A'}`).moveDown(0.5);
    doc.fontSize(10).text(`Middlewares: ${route.middlewares.join(', ')}`).moveDown(2);
  });

  // Finalize the PDF and end the stream
  doc.end();
}

// Generate the PDF
generatePDF()
  .then(() => {
    console.log('PDF report generated successfully!');
  })
  .catch((error) => {
    console.error('Error generating PDF report:', error);
  });

module.exports = { generatePDF };
