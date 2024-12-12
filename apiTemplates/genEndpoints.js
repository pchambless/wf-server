require('module-alias/register');
const express = require('express');
const fs = require('fs');
const path = require('path');
const eventRoutes = require('@middleware/events/eventRoutes');
const router = express.Router(); // Ensure the router is defined here

const apiDir = path.join(__dirname, '../api');
const templatesDir = path.join(__dirname, '../apiTemplates');

// Helper function to delete all files and folders under a directory
const deleteAllFilesAndFolders = (dirPath) => {
  if (fs.existsSync(dirPath)) {
    fs.readdirSync(dirPath).forEach((file) => {
      const currentPath = path.join(dirPath, file);
      if (fs.lstatSync(currentPath).isDirectory()) {
        deleteAllFilesAndFolders(currentPath); // Recursively delete contents
      } else {
        fs.unlinkSync(currentPath);
      }
    });
    fs.rmdirSync(dirPath); // Remove the empty directory itself
    console.log(`[DELETE] Removed directory: ${dirPath}`);
  }
};

// Clean up the entire api directory
const cleanApiDirectory = () => {
  deleteAllFilesAndFolders(apiDir);
  fs.mkdirSync(apiDir); // Recreate the base api directory
  console.log(`[CREATE] Recreated base directory: ${apiDir}`);
};

// Helper function to ensure directory exists
const ensureDirectoryExistence = (filePath) => {
  const dirname = path.dirname(filePath);
  if (fs.existsSync(dirname)) {
    return true;
  }
  ensureDirectoryExistence(dirname);
  fs.mkdirSync(dirname);
  console.log(`[CREATE] Created directory: ${dirname}`);
};

// Generate new files based on eventRoutes
const generateFile = (templatePath, outputPath, replacements) => {
  ensureDirectoryExistence(outputPath);
  let content = fs.readFileSync(templatePath, 'utf8');
  Object.keys(replacements).forEach(key => {
    const regex = new RegExp(`{{${key}}}`, 'g');
    content = content.replace(regex, replacements[key]);
  });
  fs.writeFileSync(outputPath, content, 'utf8');
  console.log(`[GENERATE] Created file at: ${outputPath}`);
};

// Generate endpoints
const generateEndpoints = () => {
  const generatedFiles = [];

  eventRoutes.forEach(route => {
    const { eventType, method, path: routePath, params, qrySQL, bodyCols } = route;
    const codeName = `[${eventType}.js]`;
    const replacements = {
      eventType,
      params: params.replace(/[{}`\n]/g, ''),
      qrySQL,
      bodyCols: bodyCols ? bodyCols.replace(/[{}`\n]/g, '').split(' ').join(', ') : ''
    };

    const outputPath = path.join(__dirname, '../', routePath);
    generatedFiles.push(routePath);

    console.log(`${codeName} Processing route: ${method} ${routePath}`);

    switch (method) {
      case 'GET':
        generateFile(path.join(templatesDir, 'get.js'), outputPath, replacements);
        break;
      case 'POST':
        generateFile(path.join(templatesDir, 'post.js'), outputPath, replacements);
        break;
      case 'PATCH':
        generateFile(path.join(templatesDir, 'patch.js'), outputPath, replacements);
        break;
      case 'SDELETE':
        generateFile(path.join(templatesDir, 'softDelete.js'), outputPath, replacements);
        break;
      default:
        console.log(`[WARNING] Unsupported method ${method} for route ${routePath}`);
    }

    console.log(`${codeName} ${method} ${routePath} generated`);
  });
};

// Clean up the api directory and generate new endpoints
cleanApiDirectory();
generateEndpoints();

module.exports = router; // Ensure the router is properly exported
