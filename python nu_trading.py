import numpy as np
import pandas as pd
import yfinance as yf
from datetime import datetime, timedelta
import matplotlib.pyplot as plt

class ThermodynamicTrading:
    def __init__(self, base_temp=15, max_heat=100):
        self.base_temp = base_temp
        self.max_heat = max_heat
        self.positions = {}
        self.system_entropy = 0
        
    def fetch_data(self, ticker='NU'):
        """Fetch all available historical data for NU"""
        end_date = datetime.now()
        # NU IPO was in December 2021
        start_date = datetime(2021, 12, 9)
        data = yf.download(ticker, start=start_date, end=end_date)
        data['returns'] = data['Adj Close'].pct_change()
        return data.dropna()
        
    def calculate_temperature(self, returns, window=20):
        """Calculate market temperature using rolling volatility"""
        vol = returns.rolling(window=window).std()
        annualized_vol = vol * np.sqrt(252)
        return annualized_vol
        
    def calculate_entropy(self, returns, bins=50):
        """Calculate market entropy using return distribution"""
        hist, _ = np.histogram(returns, bins=bins, density=True)
        prob = hist / hist.sum()
        return -np.sum(prob * np.log(prob + 1e-10))
        
    def calculate_system_heat(self):
        """Calculate total system heat"""
        return sum(abs(size) for size in self.positions.values())
        
    def calculate_position_size(self, equity, state):
        """Calculate position size based on system state"""
        temp_ratio = self.base_temp / state['temperature']
        entropy_factor = np.exp(-state['entropy']/2)
        heat_factor = 1 - (state['heat'] / self.max_heat)
        
        # Base position size (1% of equity)
        base_size = equity * 0.01
        
        # Adjust size based on thermodynamic factors
        size = base_size * temp_ratio**2 * entropy_factor * heat_factor
        
        # Apply risk limits
        max_size = equity * 0.02  # 2% maximum position size
        return min(size, max_size)
        
    def run_backtest(self, equity=100000):
        """Run backtest on NU data"""
        data = self.fetch_data()
        results = pd.DataFrame(index=data.index)
        
        # Calculate system states
        results['temperature'] = self.calculate_temperature(data['returns'])
        results['entropy'] = self.calculate_entropy(data['returns'])
        results['heat'] = 0  # Initialize heat
        
        # Calculate position sizes
        for i in range(len(results)):
            state = {
                'temperature': results['temperature'].iloc[i],
                'entropy': results['entropy'].iloc[i],
                'heat': results['heat'].iloc[i]
            }
            size = self.calculate_position_size(equity, state)
            results.loc[results.index[i], 'position_size'] = size
            
        # Calculate performance metrics
        results['returns'] = data['returns']
        results['strategy_returns'] = results['position_size'].shift(1) * results['returns']
        results['equity_curve'] = (1 + results['strategy_returns']).cumprod() * equity
        
        return results
        
    def plot_results(self, results):
        """Plot backtest results"""
        fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(12, 15))
        
        # Plot equity curve
        results['equity_curve'].plot(ax=ax1)
        ax1.set_title('Strategy Equity Curve')
        ax1.set_ylabel('Portfolio Value ($)')
        
        # Plot temperature
        results['temperature'].plot(ax=ax2)
        ax2.set_title('Market Temperature')
        ax2.set_ylabel('Temperature')
        
        # Plot position sizes
        results['position_size'].plot(ax=ax3)
        ax3.set_title('Position Sizes')
        ax3.set_ylabel('Position Size ($)')
        
        plt.tight_layout()
        return fig

# Run the system
system = ThermodynamicTrading()
results = system.run_backtest()

# Calculate key metrics
total_return = (results['equity_curve'].iloc[-1] / results['equity_curve'].iloc[0] - 1) * 100
sharpe_ratio = np.sqrt(252) * results['strategy_returns'].mean() / results['strategy_returns'].std()
max_drawdown = (results['equity_curve'] / results['equity_curve'].cummax() - 1).min() * 100

print(f"Total Return: {total_return:.2f}%")
print(f"Sharpe Ratio: {sharpe_ratio:.2f}")
print(f"Maximum Drawdown: {max_drawdown:.2f}%")

# Plot results
system.plot_results(results)
plt.show()