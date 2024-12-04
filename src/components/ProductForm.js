import React from 'react';

const ProductForm = ({ onSubmit, children }) => {
  return (
    <form onSubmit={onSubmit} className="w-full max-w-md p-8 bg-product-bg border-3 border-product-brdr rounded-lg shadow-lg">
      {children}
    </form>
  );
};

export default ProductForm;
