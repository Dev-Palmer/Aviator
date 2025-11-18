import React from 'react';

const Controls = () => {
  return (
    <div className="controls">
      <div className="input-group">
        <input type="number" placeholder="Bet Amount" />
        <button>Bet</button>
      </div>
      <div className="input-group">
        <input type="number" placeholder="Auto Cash Out" />
        <button>Auto</button>
      </div>
      <button className="cashout">Cash Out</button>
    </div>
  );
};

export default Controls;
