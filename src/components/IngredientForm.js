import React from 'react';

const IngredientForm = ({ onSubmit, children }) => {
  return (
    <form onSubmit={onSubmit} className="w-full max-w-md p-8 bg-ingredient-bg border-3 border-ingredient-brdr rounded-lg shadow-lg">
      {children}
    </form>
  );
};

export default IngredientForm;
