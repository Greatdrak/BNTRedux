import { useEffect } from 'react';

export type BackgroundType = 'space' | 'port-ore' | 'port-organics' | 'port-goods' | 'port-energy' | 'port-special';

export function useBackground(backgroundType: BackgroundType) {
  useEffect(() => {
    const body = document.body;
    
    // Remove all background classes
    body.classList.remove(
      'background-space', 
      'background-port-ore', 
      'background-port-organics', 
      'background-port-goods', 
      'background-port-energy', 
      'background-port-special'
    );
    
    // Add the appropriate background class
    body.classList.add(`background-${backgroundType}`);
    
    // Cleanup function to remove the class when component unmounts
    return () => {
      body.classList.remove(`background-${backgroundType}`);
    };
  }, [backgroundType]);
}
